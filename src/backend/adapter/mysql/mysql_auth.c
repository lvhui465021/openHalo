/*-------------------------------------------------------------------------
 *
 * mysql_auth.c
 *    MySQL protocol-10 greeting and mysql_native_password authentication.
 *
 * Greeting format (protocol version 10):
 *   1 byte   protocol version (10)
 *   N bytes  server version, NUL-terminated
 *   4 bytes  connection (thread) ID
 *   8 bytes  auth-plugin-data-part-1 (scramble prefix)
 *   1 byte   filler (0x00)
 *   2 bytes  capability flags (lower 16 bits)
 *   1 byte   character set (33 = utf8mb4)
 *   2 bytes  status flags
 *   2 bytes  capability flags (upper 16 bits)
 *   1 byte   length of auth-plugin-data (always 21 for mysql_native_password)
 *   10 bytes reserved (0x00)
 *   N bytes  auth-plugin-data-part-2 (scramble suffix, 12+1 for length=21)
 *   N bytes  auth-plugin name (NUL-terminated), if CLIENT_PLUGIN_AUTH set
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/adapter/mysql/mysql_auth.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "adapter/mysql/mysql_auth.h"
#include "adapter/mysql/mysql_packet.h"
#include "libpq/crypt.h"
#include "libpq/libpq-be.h"
#include "libpq/libpq.h"
#include "libpq/pqcomm.h"           /* pq_getmsgstring, etc. (may borrow)  */
#include "miscadmin.h"
#include "postmaster/protocol_routine.h"
#include "utils/memutils.h"

#include "utils/elog.h"

#include <string.h>
#include <stdlib.h>

/* ----------------------------------------------------------------
 *    Capability flags we advertise
 * ----------------------------------------------------------------
 */
#define CLIENT_LONG_PASSWORD            0x00000001
#define CLIENT_FOUND_ROWS               0x00000002
#define CLIENT_LONG_FLAG                0x00000004
#define CLIENT_CONNECT_WITH_DB          0x00000008
#define CLIENT_PROTOCOL_41              0x00000200
#define CLIENT_TRANSACTIONS             0x00002000
#define CLIENT_SECURE_CONNECTION        0x00008000
#define CLIENT_MULTI_STATEMENTS         0x00010000
#define CLIENT_MULTI_RESULTS            0x00040000
#define CLIENT_PS_MULTI_RESULTS         0x00080000
#define CLIENT_PLUGIN_AUTH              0x00080000
#define CLIENT_PLUGIN_AUTH_LENENC       0x00200000
#define CLIENT_OPTIONAL_RESULTSET_META  0x00400000
#define CLIENT_SESSION_TRACK            0x00800000
#define CLIENT_DEPRECATE_EOF            0x01000000

/*
 * Advertise protocol-41 with modern extensions.  We intentionally
 * keep this minimal (DEPRECATE_EOF only in HI word) so that protocol
 * decisions are driven by the server's own advertised set.  Client
 * capabilities are masked against this set in the DestReceiver and
 * end_command callbacks.
 */
#define MYSQL_SERVER_CAPABILITY                                        \
        ((uint32)MYSQL_CAPABILITY_LO |                                  \
         ((uint32)MYSQL_CAPABILITY_HI << 16))

#define MYSQL_CAPABILITY_LO   (uint16)(                             \
        CLIENT_LONG_PASSWORD  | CLIENT_FOUND_ROWS    |                 \
        CLIENT_LONG_FLAG      | CLIENT_CONNECT_WITH_DB |               \
        CLIENT_PROTOCOL_41    | CLIENT_TRANSACTIONS   |                \
        CLIENT_SECURE_CONNECTION | CLIENT_MULTI_STATEMENTS | CLIENT_MULTI_RESULTS)
#define MYSQL_CAPABILITY_HI   (uint16)(                             \
        (CLIENT_PLUGIN_AUTH >> 16)           |                          \
        (CLIENT_PLUGIN_AUTH_LENENC >> 16)    |                          \
        (CLIENT_DEPRECATE_EOF >> 16) | (CLIENT_SESSION_TRACK >> 16))

/* Scramble length: part1 = 8, part2 = 12, total = 20. */
#define MYSQL_SCRAMBLE_LEN          20
#define MYSQL_SCRAMBLE_PART1_LEN    8
#define MYSQL_SCRAMBLE_PART2_LEN    12
#define MYSQL_AUTH_PLUGIN_DATA_LEN  21   /* includes a trailing NUL */

/* Default utf8mb4 character set. */
#define MYSQL_CHARSET_UTF8MB4       45

/*
 * Per-connection auth state stored in port->protocol_state during the
 * login exchange.  Freed after authentication completes.
 */
typedef struct MysAuthState
{
    uint8       scramble[MYSQL_SCRAMBLE_LEN];   /* 20-byte random challenge */
    char        auth_plugin_data[MYSQL_AUTH_PLUGIN_DATA_LEN];  /* 8+13, NUL-padded */

    /* Saved login-packet fields — verified in authenticate(). */
    uint8       auth_response[MYSQL_SCRAMBLE_LEN]; /* client's scramble response */
    size_t      auth_response_len;
    /* port->user_name and port->compat_database_name already set. */
} MysAuthState;

/* ----------------------------------------------------------------
 *    Helper: generate random bytes
 * ----------------------------------------------------------------
 */
static void
generate_scramble(uint8 *buf, size_t len)
{
    for (size_t i = 0; i < len; i++)
    {
        /* We avoid NUL bytes so that the auth-plugin-data is clean. */
        uint8 b;
        do
        {
            b = (uint8) (random() & 0xFF);
        } while (b == 0x00);
        buf[i] = b;
    }
}

/* ----------------------------------------------------------------
 *    mysql_send_greeting
 *
 * Builds and sends the protocol-10 handshake packet.
 * Stores the scramble in port->protocol_state.
 * ----------------------------------------------------------------
 */
void
mysql_send_greeting(MysPacketState *ps, Port *port)
{
    MysAuthState *auth;
    char        payload[256];
    int         pos = 0;
    int         server_version_len;
    uint32      thread_id;
    uint16      cap_lo = MYSQL_CAPABILITY_LO;
    uint16      cap_hi = MYSQL_CAPABILITY_HI;
    uint32      capability;
    const char *server_version = "8.0.40-openhalo-1.0";
    const char *auth_plugin_name = "caching_sha2_password";
    int         auth_plugin_name_len;
    uint8       charset = MYSQL_CHARSET_UTF8MB4;
    uint16      status_flags = 0x0002;   /* SERVER_STATUS_AUTOCOMMIT */
    uint8       filler = 0x00;
    int         reserved_len = 10;

    /* Allocate per-connection auth state. */
    auth = (MysAuthState *) MemoryContextAllocZero(TopMemoryContext,
                                                    sizeof(MysAuthState));
    generate_scramble(auth->scramble, MYSQL_SCRAMBLE_LEN);

    /* Build auth_plugin_data: part1 (8 bytes) + NUL + part2 (12 bytes). */
    memcpy(auth->auth_plugin_data, auth->scramble, MYSQL_SCRAMBLE_PART1_LEN);
    auth->auth_plugin_data[MYSQL_SCRAMBLE_PART1_LEN] = '\0';
    memcpy(auth->auth_plugin_data + MYSQL_SCRAMBLE_PART1_LEN + 1,
           auth->scramble + MYSQL_SCRAMBLE_PART1_LEN,
           MYSQL_SCRAMBLE_PART2_LEN);

    /* Store auth state in the packet state — do NOT overwrite
     * port->protocol_state (which must remain the MysPacketState). */
    mysql_packet_set_auth_state(ps, (void *) auth);

    /* Assemble packet payload. */
    server_version_len = (int) strlen(server_version);
    auth_plugin_name_len = (int) strlen(auth_plugin_name);
    thread_id = (uint32)(MyProcPid & 0xFFFFFFFF);

    capability = ((uint32) cap_hi << 16) | (uint32) cap_lo;

    /* Protocol version */
    payload[pos++] = 10;

    /* Server version + NUL */
    memcpy(payload + pos, server_version, server_version_len);
    pos += server_version_len;
    payload[pos++] = '\0';

    /* Connection ID */
    memcpy(payload + pos, &thread_id, 4);
    pos += 4;

    /* Auth-plugin-data part 1 */
    memcpy(payload + pos, auth->auth_plugin_data, MYSQL_SCRAMBLE_PART1_LEN);
    pos += MYSQL_SCRAMBLE_PART1_LEN;

    /* Filler */
    payload[pos++] = (char) filler;

    /* Capability flags (lower 16) */
    memcpy(payload + pos, &cap_lo, 2);
    pos += 2;

    /* Character set */
    payload[pos++] = (char) charset;

    /* Status flags */
    memcpy(payload + pos, &status_flags, 2);
    pos += 2;

    /* Capability flags (upper 16) */
    memcpy(payload + pos, &cap_hi, 2);
    pos += 2;

    /* Length of auth-plugin-data */
    payload[pos++] = (char) MYSQL_AUTH_PLUGIN_DATA_LEN;

    /* Reserved (10 bytes of 0x00) */
    memset(payload + pos, 0, reserved_len);
    pos += reserved_len;

    /* Auth-plugin-data part 2 (13 bytes: 12 scramble + 1 NUL for length=21) */
    memcpy(payload + pos,
           auth->auth_plugin_data + MYSQL_SCRAMBLE_PART1_LEN + 1,
           MYSQL_SCRAMBLE_PART2_LEN);
    pos += MYSQL_SCRAMBLE_PART2_LEN;
    /* auth_plugin_data_len=21 means part2 is 13 bytes (12 scramble + NUL) */
    payload[pos++] = '\0';

    /* Auth plugin name + NUL */
    if (capability & CLIENT_PLUGIN_AUTH)
    {
        memcpy(payload + pos, auth_plugin_name, auth_plugin_name_len);
        pos += auth_plugin_name_len;
        payload[pos++] = '\0';
    }

    mysql_packet_write(ps, payload, (size_t) pos);

    /*
     * After sending the greeting (seq 0), the client will respond at
     * seq 1.  Set ps->seq to 1 so mysql_packet_read accepts the login
     * packet without a sequence-number mismatch error.
     */
    mysql_packet_set_seq(ps, 1);
}

/* ----------------------------------------------------------------
 *    parse_client_capabilities
 *
 * Reads the 4-byte client capability word from the login packet.
 * Returns true if the packet contains CLIENT_PROTOCOL_41.
 * ----------------------------------------------------------------
 */
static bool
parse_client_capabilities(const char *payload, size_t len,
                          uint32 *capability, char **charset)
{
    if (len < 4)
        return false;
    *capability = ((uint32)(uint8)payload[0])
                | ((uint32)(uint8)payload[1] << 8)
                | ((uint32)(uint8)payload[2] << 16)
                | ((uint32)(uint8)payload[3] << 24);
    *charset = NULL;   /* not extracted separately for M1 */
    return true;
}

/* ----------------------------------------------------------------
 *    mysql_verify_login
 *
 * Read login packet, verify mysql_native_password response against
 * the challenge stored in port->protocol_state, perform HBA lookup,
 * and fill in port->user_name / port->compat_database_name.
 * ----------------------------------------------------------------
 */
int
mysql_verify_login(MysPacketState *ps, Port *port)
{
    MysAuthState *auth = (MysAuthState *) mysql_packet_get_auth_state(ps);
    char       *payload;
    size_t      len;
    uint32      client_cap;
    uint32      max_packet_size;
    char       *charset_ptr;
    const char *pos_ptr;
    size_t      remaining;
    const char *username = NULL;
    const char *auth_response = NULL;
    size_t      auth_response_len = 0;
    const char *schema_name = NULL;
    const char *auth_plugin_name = NULL;

    /* Read the login (handshake response) packet. */
    if (!mysql_packet_read(ps, &payload, &len))
    {
        ereport(COMMERROR,
                (errmsg("failed to read MySQL login packet")));
        return STATUS_ERROR;
    }

    if (len < 36)
    {
        ereport(COMMERROR,
                (errmsg("MySQL login packet too short (%zu bytes)", len)));
        pfree(payload);
        return STATUS_ERROR;
    }

    /*
     * The handshake sequence is shared: greeting=0, login=1, response=2.
     * After mysql_packet_read consumed the login packet (client seq 1),
     * set server_seq to 2 so that any ERR/OK packet written from this
     * function or from mysql_perform_authentication carries the correct
     * sequence number.
     */
    mysql_packet_set_server_seq(ps, 2);

    pos_ptr = payload;
    remaining = len;

    /* --- Parse client capability flags (4 bytes) --- */
    if (!parse_client_capabilities(pos_ptr, remaining, &client_cap, &charset_ptr))
    {
        pfree(payload);
        return STATUS_ERROR;
    }

    /* Store client capabilities so DestReceiver / end_command can consult them. */
    mysql_packet_set_client_caps(ps, client_cap);

    pos_ptr += 4;
    remaining -= 4;

    /* --- Max packet size (4 bytes) --- */
    if (remaining < 4) { pfree(payload); return STATUS_ERROR; }
    memcpy(&max_packet_size, pos_ptr, 4);
    pos_ptr += 4;
    remaining -= 4;

    /* --- Character set (1 byte) --- */
    if (remaining < 1) { pfree(payload); return STATUS_ERROR; }
    pos_ptr += 1;
    remaining -= 1;

    /* --- Reserved (23 bytes of 0x00) --- */
    if (remaining < 23) { pfree(payload); return STATUS_ERROR; }
    pos_ptr += 23;
    remaining -= 23;

    /* --- Username (NUL-terminated) --- */
    username = pos_ptr;
    {
        size_t ulen = strnlen(pos_ptr, remaining);
        if (ulen >= remaining) { pfree(payload); return STATUS_ERROR; }
        pos_ptr += ulen + 1;
        remaining -= ulen + 1;
    }

    /* --- Auth response (length-encoded) --- */
    if (remaining < 1) { pfree(payload); return STATUS_ERROR; }
    {
        uint8 auth_len = (uint8) *pos_ptr;
        pos_ptr += 1;
        remaining -= 1;
        if (remaining < auth_len) { pfree(payload); return STATUS_ERROR; }
        auth_response = pos_ptr;
        auth_response_len = auth_len;
        pos_ptr += auth_len;
        remaining -= auth_len;
    }

    /* --- Schema name (NUL-terminated, if CLIENT_CONNECT_WITH_DB) --- */
    if ((client_cap & CLIENT_CONNECT_WITH_DB) && remaining > 0)
    {
        size_t slen = strnlen(pos_ptr, remaining);
        if (slen > 0 && slen < remaining)
        {
            schema_name = pos_ptr;
            pos_ptr += slen + 1;
            remaining -= slen + 1;
        }
    }


    /* --- Auth plugin name (NUL-terminated, if CLIENT_PLUGIN_AUTH) --- */
    if ((client_cap & CLIENT_PLUGIN_AUTH) && remaining > 0)
    {
        size_t plen = strnlen(pos_ptr, remaining);
        if (plen > 0)
            auth_plugin_name = pos_ptr;
    }

    /* --- Validate --- */
    if (username == NULL || strlen(username) == 0)
    {
        mysql_packet_write_err(ps, 1045, "28000",
                               "Access denied for user '' (no username)");
        pfree(payload);
        return STATUS_ERROR;
    }

    if (auth_response == NULL || auth_response_len == 0)
    {
        mysql_packet_write_err(ps, 1045, "28000",
                               "Access denied for user '%s' (empty password)",
                               username);
        pfree(payload);
        return STATUS_ERROR;
    }

    /*
     * MySQL 8.0+ clients default to caching_sha2_password.  We implement
     * the auth-switch protocol: route SHA2 requests to mysql_native_password
     * via an Auth Switch Request packet (0xFE header).  This triggers the
     * client's auth-switch state machine, matching the real MySQL 8.0 flow
     * where the server lacks a cached SHA2 hash and redirects to native.
     */
    if (auth_plugin_name != NULL &&
        strcmp(auth_plugin_name, "caching_sha2_password") == 0)
    {
        /*
         * Build Auth Switch Request:
         *   0xFE marker + plugin_name(NUL) + plugin_data(20-byte scramble + NUL)
         */
        char switch_pkt[64];
        int  sw_pos = 0;
        const char *target_plugin = "mysql_native_password";
        int  target_plugin_len = (int) strlen(target_plugin);

        switch_pkt[sw_pos++] = (char) 0xFE;    /* auth-switch marker */
        memcpy(switch_pkt + sw_pos, target_plugin, target_plugin_len);
        sw_pos += target_plugin_len;
        switch_pkt[sw_pos++] = '\0';
        /* Append 21 bytes of auth-plugin-data: 20-byte scramble + NUL */
        memcpy(switch_pkt + sw_pos, auth->auth_plugin_data, MYSQL_AUTH_PLUGIN_DATA_LEN);
        sw_pos += MYSQL_AUTH_PLUGIN_DATA_LEN;

        /*
         * The handshake sequence is shared: greeting=0, login=1,
         * auth-switch=2.  Set server_seq to 2 before writing the
         * Auth Switch Request so the client receives it at the
         * sequence number it expects after sending the login at seq 1.
         */
        mysql_packet_set_server_seq(ps, 2);

        mysql_packet_write(ps, switch_pkt, (size_t) sw_pos);

        /*
         * After the Auth Switch Request (server seq 2), the client
         * responds with its native-password auth at seq 3.
         * Set ps->seq to 3 so mysql_packet_read accepts it.
         */
        mysql_packet_set_seq(ps, 3);

        /* Read the client's native-password response to our switch request */
        {
            char       *sw_payload;
            size_t      sw_len;
            const char *sw_auth = NULL;
            size_t      sw_auth_len = 0;
            const char *sw_pos_ptr;
            size_t      sw_rem;

            if (!mysql_packet_read(ps, &sw_payload, &sw_len))
            {
                pfree(payload);
                return STATUS_ERROR;
            }

            /* Parse auth response: skip capabilities(4) + max_pkt(4) + charset(1) + reserved(23) + username(NUL) */
            if (sw_len < 32) { pfree(sw_payload); pfree(payload); return STATUS_ERROR; }
            sw_pos_ptr = sw_payload + 32;
            sw_rem = sw_len - 32;

            /* Skip username (NUL-terminated) */
            {
                size_t ulen = strnlen(sw_pos_ptr, sw_rem);
                if (ulen >= sw_rem) { pfree(sw_payload); pfree(payload); return STATUS_ERROR; }
                sw_pos_ptr += ulen + 1;
                sw_rem -= ulen + 1;
            }

            /* Auth response (length-encoded) */
            if (sw_rem < 1) { pfree(sw_payload); pfree(payload); return STATUS_ERROR; }
            {
                uint8 sw_auth_len_byte = (uint8) *sw_pos_ptr;
                sw_pos_ptr += 1;
                sw_rem -= 1;
                if (sw_rem < sw_auth_len_byte) { pfree(sw_payload); pfree(payload); return STATUS_ERROR; }
                sw_auth = sw_pos_ptr;
                sw_auth_len = sw_auth_len_byte;
            }

            /* Save the native-password auth response */
            if (sw_auth_len > MYSQL_SCRAMBLE_LEN)
                sw_auth_len = MYSQL_SCRAMBLE_LEN;
            memcpy(auth->auth_response, sw_auth, sw_auth_len);
            auth->auth_response_len = sw_auth_len;

            pfree(sw_payload);
        }

        /*
         * After the auth switch: client sent at seq 3, server must
         * respond with OK at seq 4.  Position server_seq for
         * mysql_perform_authentication.
         */
        mysql_packet_set_server_seq(ps, 4);
    }
    else if (auth_plugin_name != NULL &&
             strcmp(auth_plugin_name, "mysql_native_password") != 0)
    {
        mysql_packet_write_err(ps, 1045, "28000",
                               "Authentication plugin '%s' is not supported",
                               auth_plugin_name);
        pfree(payload);
        return STATUS_ERROR;
    }

    /* Save auth response for the authenticate callback. */
    if (auth_response_len > MYSQL_SCRAMBLE_LEN)
        auth_response_len = MYSQL_SCRAMBLE_LEN;
    memcpy(auth->auth_response, auth_response, auth_response_len);
    auth->auth_response_len = auth_response_len;

    /* Set port fields — these are needed before InitPostgres().
     * port->database_name must always be set because BackendInitialize
     * dereferences it (and PostgresMain passes it to InitPostgres).
     * MySQL connections use the configured mysql.backend_database (default
     * "postgres"), but since GUCs aren't available yet we hardcode the
     * same default. */
    port->user_name = MemoryContextStrdup(TopMemoryContext, username);
    port->database_name = MemoryContextStrdup(TopMemoryContext, "postgres");
    if (schema_name != NULL && schema_name[0] != '\0')
        port->compat_database_name = MemoryContextStrdup(TopMemoryContext,
                                                          schema_name);

    pfree(payload);

    /*
     * We return STATUS_OK so that BackendInitialize proceeds to PostgresMain,
     * which will call InitPostgres and then the authenticate callback.
     * The actual password verification happens in mysql_perform_authentication().
     */
    return STATUS_OK;
}

/* ----------------------------------------------------------------
 *    mysql_perform_authentication
 *
 * Phase B: HBA lookup and password verification.  Called from
 * ProtocolRoutine.authenticate after InitPostgres has catalog access.
 * ----------------------------------------------------------------
 */
void
mysql_perform_authentication(MysPacketState *ps, Port *port)
{
    MysAuthState *auth = (MysAuthState *) mysql_packet_get_auth_state(ps);
    char         *shadow_pass;
    const char   *logdetail;
    int           auth_result;


    if (auth == NULL)
    {
        mysql_packet_write_err(ps, 1045, "28000",
                               "Internal error: no auth state");
        ereport(FATAL,
                (errcode(ERRCODE_PROTOCOL_VIOLATION),
                 errmsg("MySQL authentication failed: no auth state")));
    }

    shadow_pass = get_role_password(port->user_name, &logdetail);
    if (shadow_pass == NULL)
    {
        mysql_packet_write_err(ps, 1045, "28000",
                               "Access denied for user '%s' (role does not exist)",
                               port->user_name);
        ereport(FATAL,
                (errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
                 errmsg("MySQL authentication failed for user \"%s\"",
                        port->user_name)));
    }

    auth_result = mysql_native_password_verify(port->user_name, shadow_pass,
                                                auth->auth_response,
                                                auth->auth_response_len,
                                                auth->scramble,
                                                MYSQL_SCRAMBLE_LEN,
                                                &logdetail);
    pfree(shadow_pass);

    if (auth_result != STATUS_OK)
    {
        mysql_packet_write_err(ps, 1045, "28000",
                               "Access denied for user '%s' (password mismatch)",
                               port->user_name);
        ereport(FATAL,
                (errcode(ERRCODE_INVALID_PASSWORD),
                 errmsg("MySQL authentication failed for user \"%s\": password mismatch",
                        port->user_name)));
    }


    /*
     * Send the MySQL OK packet.  This is the server's response to the login
     * packet — the client has been waiting for this since sending its
     * handshake response.
     *
     * Sequence numbers during handshake are shared: greeting=0, login=1,
     * OK=2 (or greeting=0, login=1, auth-switch=2, client=3, OK=4).
     * server_seq is already positioned correctly by mysql_verify_login.
     */
    {
        char ok[7];
        int  okpos = 0;
        ok[okpos++] = 0x00;                      /* OK header */
        ok[okpos++] = 0x00;                      /* affected rows = 0 */
        ok[okpos++] = 0x00;                      /* last insert id = 0 */
        ok[okpos++] = 0x02; ok[okpos++] = 0x00;  /* status: autocommit */
        ok[okpos++] = 0x00; ok[okpos++] = 0x00;  /* warnings: 0 */
        mysql_packet_write_ok(ps, ok, (size_t) okpos, 0x00);
    }

    /*
     * Flush the OK packet to the client immediately.  secure_write() may
     * buffer data in the SSL layer; without this flush the client never
     * sees the OK, waits forever, and eventually closes the connection.
     * openHalo's netTransceiver->finishWriteToBufFlush serves the same role.
     */
    pq_flush();

    /*
     * The handshake is complete.  Reset both sequence counters for the
     * command phase.  The client will send commands at seq 0 and the
     * server responds starting at seq 1 (shared sequence space).
     */
    mysql_packet_reset_seq(ps);
    mysql_packet_set_server_seq(ps, 1);

    /*
     * The MysPacketState (port->protocol_state) stays alive for the
     * lifetime of the session — it is used by every I/O callback.
     * Do NOT free it here.
     */
}

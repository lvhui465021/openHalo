/*-------------------------------------------------------------------------
 *
 * mysql_packet.c
 *    MySQL packet-layer I/O: header read/write, sequence tracking,
 *    multi-packet reassembly, and ERR-packet formatting.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/adapter/mysql/mysql_packet.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "adapter/mysql/mysql_packet.h"
#include "libpq/libpq.h"
#include "miscadmin.h"
#include "utils/elog.h"

#include <errno.h>
#include <stdarg.h>

/* ----------------------------------------------------------------
 *    MysPacketState
 * ----------------------------------------------------------------
 */
struct MysPacketState
{
    Port       *port;               /* MyProcPort (socket, secure_read/write) */
    uint8       seq;                /* next expected client sequence number    */
    uint8       server_seq;         /* next server sequence number to send     */
    bool        greeting_sent;      /* has the server greeting been emitted?   */
    void       *auth_state;         /* MysAuthState during handshake, else NULL */
    uint32      client_capabilities; /* client capability flags from login     */
};

/* ----------------------------------------------------------------
 *    Lifecycle
 * ----------------------------------------------------------------
 */
MysPacketState *
mysql_packet_create(Port *port)
{
    MysPacketState *ps;

    ps = (MysPacketState *) palloc0(sizeof(MysPacketState));
    ps->port = port;
    ps->seq = 0;           /* client starts at seq 0 after server greeting   */
    ps->server_seq = 0;    /* greeting is seq 0                              */
    ps->greeting_sent = false;

    return ps;
}

void
mysql_packet_free(MysPacketState *ps)
{
    if (ps != NULL)
        pfree(ps);
}

/* ----------------------------------------------------------------
 *    Low-level read
 * ----------------------------------------------------------------
 */
bool
mysql_packet_read(MysPacketState *ps, char **payload, size_t *len)
{
    uint8       header[MYSQL_PACKET_HEADER_SIZE];
    ssize_t     nread;
    uint32      payload_len;
    uint8       pkt_seq;
    char       *buf;
    Port       *port = MyProcPort;

    /* read 4-byte header (retry on EINTR/EAGAIN in non-blocking mode) */
    do {
        nread = secure_read(port, header, MYSQL_PACKET_HEADER_SIZE);
    } while (nread < 0 && (errno == EINTR || errno == EAGAIN));
    if (nread != MYSQL_PACKET_HEADER_SIZE)
    {
        if (nread < 0)
            ereport(COMMERROR,
                    (errcode_for_socket_access(),
                     errmsg("could not read MySQL packet header: %m")));
        return false;
    }

    payload_len = (uint32) header[0]
                | ((uint32) header[1] << 8)
                | ((uint32) header[2] << 16);
    pkt_seq = header[3];

    if (pkt_seq != ps->seq && !ps->greeting_sent)
    {
        /* Before greeting is sent, we are reading the login packet;
         * the client starts its sequence at 0.  Accept either. */
        ps->seq = pkt_seq;
    }
    else if (pkt_seq != ps->seq)
    {
        ereport(COMMERROR,
                (errmsg("MySQL packet sequence number mismatch: expected %u, got %u",
                        ps->seq, pkt_seq)));
        return false;
    }

    ps->seq = (ps->seq + 1) & 0xFF;

    /* allocate and read payload */
    buf = (char *) palloc(payload_len + 1);
    if (payload_len > 0)
    {
        do {
            nread = secure_read(port, buf, payload_len);
        } while (nread < 0 && (errno == EINTR || errno == EAGAIN));
        if (nread != (ssize_t) payload_len)
        {
            pfree(buf);
            if (nread < 0)
                ereport(COMMERROR,
                        (errcode_for_socket_access(),
                         errmsg("could not read MySQL packet payload: %m")));
            return false;
        }
    }
    buf[payload_len] = '\0';

    *payload = buf;
    *len = (size_t) payload_len;
    return true;
}

/* ----------------------------------------------------------------
 *    Low-level write
 * ----------------------------------------------------------------
 */
static void
mysql_write_raw(MysPacketState *ps, const char *payload, size_t len)
{
    uint8       header[MYSQL_PACKET_HEADER_SIZE];
    ssize_t     written;
    Port       *port = MyProcPort;

    header[0] = (uint8) (len & 0xFF);
    header[1] = (uint8) ((len >> 8) & 0xFF);
    header[2] = (uint8) ((len >> 16) & 0xFF);
    header[3] = ps->server_seq;

    ps->server_seq = (ps->server_seq + 1) & 0xFF;

    do {
        written = secure_write(port, header, MYSQL_PACKET_HEADER_SIZE);
    } while (written < 0 && (errno == EINTR || errno == EAGAIN));
    if (written != MYSQL_PACKET_HEADER_SIZE)
        goto write_fail;

    if (len > 0)
    {
        do {
            written = secure_write(port, payload, len);
        } while (written < 0 && (errno == EINTR || errno == EAGAIN));
        if (written != (ssize_t) len)
            goto write_fail;
    }

    return;

write_fail:
    ereport(COMMERROR,
            (errcode_for_socket_access(),
             errmsg("could not write to MySQL client: %m")));
    /* The caller is expected to handle the dead connection. */
}

void
mysql_packet_write(MysPacketState *ps, const char *payload, size_t len)
{
    mysql_write_raw(ps, payload, len);
}

void
mysql_packet_write_ok(MysPacketState *ps,
                      const char *payload, size_t len,
                      uint8 header_byte)
{
    /*
     * Send the payload as a single MySQL packet.  The caller is responsible
     * for including the OK/ERR/EOF header byte (0x00 / 0xFF / 0xFE) as the
     * first byte of payload.  The header_byte parameter is informational
     * (unused in the framing itself) — kept for API compatibility.
     */
    (void) header_byte;
    mysql_write_raw(ps, payload, len);
}

void
mysql_packet_write_err(MysPacketState *ps,
                       uint16 errcode,
                       const char *sqlstate,
                       const char *fmt, ...)
{
    /*
     * Build a MySQL ERR packet:
     *   1 byte  header (0xFF)
     *   2 bytes error code (little-endian)
     *   1 byte  SQLSTATE marker '#'
     *   5 bytes SQLSTATE string (e.g. "28000")
     *   N bytes human-readable message (no trailing NUL, but we include one
     *     for ease of construction and subtract it at the end.)
     */
    char        msgbuf[512];
    va_list     args;
    int         msglen;
    size_t      payload_len;
    char       *payload;
    int         pos = 0;

    va_start(args, fmt);
    msglen = vsnprintf(msgbuf, sizeof(msgbuf), fmt, args);
    va_end(args);

    /*
     * MySQL ERR packet payload:
     *   1 byte  header (0xFF)
     *   2 bytes error code (little-endian)
     *   1 byte  SQLSTATE marker '#'
     *   5 bytes SQLSTATE string (e.g. "28000")
     *   N bytes human-readable message (no trailing NUL)
     *
     * Note: mysql_packet_write_ok() ignores its header_byte parameter,
     * so the 0xFF marker MUST be embedded in the payload here.  EOF (0xFE)
     * and OK (0x00) packets follow the same convention — the caller bakes
     * the header into the payload.
     */
    payload_len = 1 + 2 + 1 + 5 + (size_t) msglen;
    payload = (char *) palloc(payload_len);

    payload[pos++] = (char) 0xFF;   /* ERR marker */
    payload[pos++] = (char) (errcode & 0xFF);
    payload[pos++] = (char) ((errcode >> 8) & 0xFF);
    payload[pos++] = '#';
    if (sqlstate != NULL)
    {
        memcpy(payload + pos, sqlstate, 5);
        pos += 5;
    }
    else
    {
        memset(payload + pos, ' ', 5);
        pos += 5;
    }
    memcpy(payload + pos, msgbuf, (size_t) msglen);
    pos += msglen;

    mysql_packet_write_ok(ps, payload, (size_t) pos, 0xFF);
    pfree(payload);
}

void
mysql_packet_reset_seq(MysPacketState *ps)
{
    if (ps != NULL)
    {
        ps->seq = 0;
        ps->server_seq = 0;
    }
}

void
mysql_packet_set_server_seq(MysPacketState *ps, uint8 seq)
{
    if (ps != NULL)
        ps->server_seq = seq;
}

void
mysql_packet_set_auth_state(MysPacketState *ps, void *state)
{
    if (ps != NULL)
        ps->auth_state = state;
}

void *
mysql_packet_get_auth_state(MysPacketState *ps)
{
    if (ps != NULL)
        return ps->auth_state;
    return NULL;
}

void
mysql_packet_set_client_caps(MysPacketState *ps, uint32 caps)
{
    if (ps != NULL)
        ps->client_capabilities = caps;
}

uint32
mysql_packet_get_client_caps(MysPacketState *ps)
{
    if (ps != NULL)
        return ps->client_capabilities;
    return 0;
}

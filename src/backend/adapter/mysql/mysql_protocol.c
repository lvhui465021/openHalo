/*-------------------------------------------------------------------------
 *
 * mysql_protocol.c
 *    MySQL ProtocolRoutine vtable: lifecycle, I/O, DestReceiver, and
 *    error-encoding callbacks.
 *
 * A single const ProtocolRoutine instance is created and registered at
 * _PG_init time so that postmaster startup can resolve it.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/adapter/mysql/mysql_protocol.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/printtup.h"
#include "access/xact.h"
#include "adapter/mysql/mysql_auth.h"
#include "adapter/mysql/mysql_command.h"
#include "adapter/mysql/mysql_packet.h"
#include "adapter/mysql/mysql_protocol.h"
#include "libpq/libpq-be.h"
#include "libpq/libpq.h"
#include "miscadmin.h"
#include "parser/parsereng.h"
#include "postmaster/protocol_routine.h"
#include "tcop/dest.h"
#include "utils/builtins.h"
#include "utils/elog.h"
#include "utils/lsyscache.h"
#include "utils/guc.h"

#include <string.h>

/* ----------------------------------------------------------------
 *    Forward declarations
 * ----------------------------------------------------------------
 */
static void mysql_init(Port *port);
static int  mysql_startup_exchange(Port *port);
static void mysql_authenticate(Port *port);

static int  mysql_read_command_cb(StringInfo inBuf);
static ProtocolCommandResult mysql_process_command(int *command,
                                                    StringInfo inBuf);
static void mysql_comm_reset(void);
static bool mysql_is_reading_msg(void);
static void mysql_send_backend_key_data_noop(int pid, const uint8 *key,
                                              int keylen);
static void mysql_session_initialize_noop(Port *port);
static void mysql_set_remote_dest_receiver_params(DestReceiver *receiver,
                                                   struct PortalData *portal);

static DestReceiver *mysql_create_dest_receiver(CommandDest dest);
static void mysql_end_command(const QueryCompletion *qc,
                              CommandDest dest,
                              bool force_undecorated_output);
static void mysql_null_command(CommandDest dest);
static void mysql_send_ready_for_query(CommandDest dest);

static void mysql_send_error(ErrorData *edata);
static void mysql_report_parameter_status(const char *name, const char *value);

/* ----------------------------------------------------------------
 *    Per-connection packet state accessor
 * ----------------------------------------------------------------
 */
static inline MysPacketState *
mysql_ps(void)
{
    return (MysPacketState *) MyProcPort->protocol_state;
}

/* ----------------------------------------------------------------
 *    Lifecycle callbacks
 * ----------------------------------------------------------------
 */
static void
mysql_init(Port *port)
{
    MysPacketState *ps;

    /*
     * Set the backend type early so that pgstat tracks our I/O operations.
     * This mirrors openHalo's adapter.c:startServer which also sets
     * MyBackendType = B_BACKEND.  Without this, the first catalog access
     * during authentication (SearchSysCache→read from disk) triggers an
     * assertion failure in pgstat_tracks_io_op() when cassert is enabled.
     */
    MyBackendType = B_BACKEND;

    ps = mysql_packet_create(port);
    port->protocol_state = (void *) ps;
}

static int
mysql_startup_exchange(Port *port)
{
    MysPacketState *ps = (MysPacketState *) port->protocol_state;
    int            status;

    Assert(ps != NULL);

    /*
     * Set the socket to blocking mode for the handshake and keep it that
     * way for the lifetime of the MySQL session.  Our packet I/O callbacks
     * use direct secure_read/secure_write with EAGAIN retry, bypassing the
     * PG FeBeWaitSet.  A non-blocking socket causes spurious ENOTSOCK
     * failures during result-set writing.
     */
    port->noblock = false;

    /* Phase A1: Send the MySQL handshake greeting. */
    mysql_send_greeting(ps, port);

    /* Phase A2: Read and verify the login response. */
    status = mysql_verify_login(ps, port);

    /*
     * Keep the socket blocking for MySQL connections.  Our packet I/O
     * callbacks (mysql_read_command_cb, mysql_packet_write, …) use direct
     * secure_read/secure_write with EAGAIN retry, bypassing the PG
     * FeBeWaitSet.  A non-blocking socket causes spurious ENOTSOCK
     * failures during result-set writing.
     */
    port->noblock = false;

    return status;
}

static void
mysql_authenticate(Port *port)
{
    /*
     * Phase B of MySQL authentication.  startup_exchange already read
     * the login packet and extracted user_name / compat_database_name.
     * Now InitPostgres has run, so we have catalog access and can
     * verify the password.
     */
    mysql_perform_authentication(mysql_ps(), port);
}

/* ----------------------------------------------------------------
 *    Command I/O callbacks
 * ----------------------------------------------------------------
 */
static int
mysql_read_command_cb(StringInfo inBuf)
{
    MysPacketState *ps = (MysPacketState *) MyProcPort->protocol_state;
    int            command;
    int            len;

    Assert(ps != NULL);

    len = mysql_read_command(ps, &command, inBuf);
    if (len < 0)
        return -1;

    /*
     * Return the pseudo-command directly.  The PostgresMain loop stores
     * this as 'firstchar' and passes it to ProtocolProcessCommand().
     */
    return command;
}

static ProtocolCommandResult
mysql_process_command(int *command, StringInfo inBuf)
{
    if (command == NULL)
        return PROTOCOL_COMMAND_PASSTHROUGH;

    switch (*command)
    {
    case MYSQL_PSEUDO_QUERY:
        if (inBuf->len > 0)
        {
            /*
             * M2: All non-empty queries now flow through the MySQL
             * parser pipeline (mys_raw_parser -> standard analyze ->
             * executor -> MySQL DestReceiver).  The inline wire-level
             * handlers for SELECT 1 / @@version / SELECT DATABASE()
             * are removed -- the MySQL parser and DestReceiver cover
             * these cases correctly.
             *
             * Unrecognized queries that cannot be parsed by the MySQL
             * grammar produce a syntax error, which is mapped to a
             * MySQL ERR packet by the protocol error encoder.
             */
            *command = 'Q';
            return PROTOCOL_COMMAND_PASSTHROUGH;
        }

        /*
         * Empty query: send a generic MySQL OK so that the client
         * protocol state machine keeps progressing.  Mirrors openHalo's
         * behavior for zero-length COM_QUERY payloads.
         */
        {
            char ok[7];
            int  pos = 0;
            ok[pos++] = 0x00;
            ok[pos++] = 0x00;
            ok[pos++] = 0x00;
            ok[pos++] = 0x02; ok[pos++] = 0x00;
            ok[pos++] = 0x00; ok[pos++] = 0x00;
            mysql_packet_write_ok(mysql_ps(), ok, (size_t) pos, 0x00);
            pq_flush();
        }
        return PROTOCOL_COMMAND_HANDLED;


    case MYSQL_PSEUDO_QUIT:
        *command = 'X';
        return PROTOCOL_COMMAND_PASSTHROUGH;

    case MYSQL_PSEUDO_PING:
        {
            char ok[7];
            int  pos = 0;
            ok[pos++] = 0x00;
            ok[pos++] = 0x00;
            ok[pos++] = 0x00;
            ok[pos++] = 0x02; ok[pos++] = 0x00;
            ok[pos++] = 0x00; ok[pos++] = 0x00;
            mysql_packet_write_ok(mysql_ps(), ok, (size_t) pos, 0x00);
            pq_flush();
        }
        return PROTOCOL_COMMAND_HANDLED;

    default:
        return PROTOCOL_COMMAND_PASSTHROUGH;
    }
}

static void
mysql_comm_reset(void)
{
    /*
     * No-op: mirror openHalo's .comm_reset = NULL.
     * MySQL protocol does NOT reset sequence numbers between commands.
     * Both ps->seq (read) and ps->server_seq (write) track independently
     * and naturally wrap at 256, which is correct per protocol spec.
     * Resetting here would break the sequence for end_command's EOF/OK.
     */
}

static bool
mysql_is_reading_msg(void)
{
    /* MySQL clients don't have a "message in progress" state like PG. */
    return false;
}

static void
mysql_send_backend_key_data_noop(int pid, const uint8 *key, int keylen)
{
    /* MySQL protocol does not use PG cancel-key packets. */
}

static void
mysql_session_initialize_noop(Port *port)
{
    /* M1: no per-session MySQL init needed beyond what init() already did. */
}

static void
mysql_set_remote_dest_receiver_params(DestReceiver *receiver,
                                       struct PortalData *portal)
{
    /*
     * No-op for MySQL DestReceiver.  SetRemoteDestReceiverParams() is
     * specific to the standard PG printtup DestReceiver (DR_printtup)
     * and would overwrite our MysDRState fields (ps, ncols, started)
     * if called here.  MySQL result-set parameters are handled directly
     * by mysDR_rStartup / mysDR_receiveSlot.
     */
    (void) receiver;
    (void) portal;
}

/* ----------------------------------------------------------------
 *    DestReceiver callbacks
 * ----------------------------------------------------------------
 */
/*
 * MySQL text-protocol DestReceiver.
 *
 * Sends MySQL text protocol result sets: column-count → column definitions
 * → EOF → row data → EOF.  Type mapping covers common scalar types.
 */
typedef struct MysDRState
{
    DestReceiver pub;           /* must be first */
    MysPacketState *ps;         /* packet I/O */
    bool         started;       /* rStartup called */
    int          ncols;         /* number of columns */
} MysDRState;

static bool
mysDR_receiveSlot(TupleTableSlot *slot, DestReceiver *self)
{
    MysDRState *dr = (MysDRState *) self;
    int         ncols;
    int         i;

    ncols = slot->tts_tupleDescriptor->natts;

    if (!dr->started)
    {
        uint32 caps = mysql_negotiated_caps(dr->ps);

        /*
         * MySQL 8.0.3+: if the client set CLIENT_OPTIONAL_RESULTSET_METADATA,
         * the column-count packet is prefixed with a 1-byte metadata_follows
         * flag (1 = full column metadata follows).
         */
        {
            char colhdr[20];
            int  pos = 0;
            if (caps & MYSQL_CAP_OPTIONAL_RESULTSET_METADATA)
                colhdr[pos++] = 1;    /* RESULTSET_METADATA_FULL */
            if (ncols < 251)
            {
                colhdr[pos++] = (char) ncols;
            }
            else if (ncols < 65536)
            {
                colhdr[pos++] = (char) 0xFC;
                colhdr[pos++] = (char) (ncols & 0xFF);
                colhdr[pos++] = (char) ((ncols >> 8) & 0xFF);
            }
            else
            {
                colhdr[pos++] = (char) 0xFD;
                colhdr[pos++] = (char) (ncols & 0xFF);
                colhdr[pos++] = (char) ((ncols >> 8) & 0xFF);
                colhdr[pos++] = (char) ((ncols >> 16) & 0xFF);
            }
            mysql_packet_write_ok(dr->ps, colhdr, (size_t) pos, 0x00);
        }

        for (i = 0; i < ncols; i++)
        {
            Form_pg_attribute attr = TupleDescAttr(slot->tts_tupleDescriptor, i);
            StringInfoData colbuf;
            initStringInfo(&colbuf);

            /*
             * MySQL ColumnDefinition41 packet (text protocol).
             * All string fields are length-encoded.
             */
            /* "def" marker */
            appendStringInfoChar(&colbuf, 3);
            appendStringInfoString(&colbuf, "def");
            /* catalog = "" */
            appendStringInfoChar(&colbuf, 0);
            /* schema = "" */
            appendStringInfoChar(&colbuf, 0);
            /* table alias (use empty for computed columns) */
            appendStringInfoChar(&colbuf, 0);
            /* org_table = "" */
            appendStringInfoChar(&colbuf, 0);
            /* col_name */
            {
                const char *cname = NameStr(attr->attname);
                int         clen = (int) strlen(cname);
                appendStringInfoChar(&colbuf, (char) clen);
                appendBinaryStringInfo(&colbuf, cname, clen);
            }
            /* org_col_name */
            {
                const char *cname = NameStr(attr->attname);
                int         clen = (int) strlen(cname);
                appendStringInfoChar(&colbuf, (char) clen);
                appendBinaryStringInfo(&colbuf, cname, clen);
            }
            /* length of fixed fields (always 0x0c = 12) */
            appendStringInfoChar(&colbuf, 0x0c);
            /* charset: utf8mb4 = 45 */
            appendStringInfoChar(&colbuf, 0x2D); appendStringInfoChar(&colbuf, 0x00);
            /* column length */
            {
                int32 collen = attr->atttypmod > 0 ? attr->atttypmod : 256;
                appendBinaryStringInfo(&colbuf, (char *)&collen, 4);
            }
            /* type: map PG type → MySQL type */
            {
                Oid  typid = attr->atttypid;
                char mysql_type;

                switch (typid)
                {
                    case INT2OID:
                    case INT4OID:
                    case INT8OID:
                        mysql_type = 8;     /* MYSQL_TYPE_LONGLONG */
                        break;
                    case FLOAT4OID:
                    case FLOAT8OID:
                    case NUMERICOID:
                        mysql_type = 246;   /* MYSQL_TYPE_NEWDECIMAL */
                        break;
                    default:
                        mysql_type = 253;   /* MYSQL_TYPE_VAR_STRING */
                        break;
                }
                appendStringInfoChar(&colbuf, mysql_type);
            }
            /* flags */
            appendStringInfoChar(&colbuf, 0x00); appendStringInfoChar(&colbuf, 0x00);
            /* decimals */
            appendStringInfoChar(&colbuf, 0x00);
            /* filler */
            appendStringInfoChar(&colbuf, 0x00); appendStringInfoChar(&colbuf, 0x00);

            mysql_packet_write_ok(dr->ps, colbuf.data, colbuf.len, 0x00);
            pfree(colbuf.data);
        }
        /*
         * After column definitions: send EOF (or skip if DEPRECATE_EOF).
         * openHalo's sendEOFPacketNoFlush is a no-op when DEPRECATE_EOF
         * is negotiated -- the client knows the metadata section ends
         * after the last ColumnDefinition41 packet.
         */
        if (!(caps & MYSQL_CAP_DEPRECATE_EOF))
        {
            char eof[5] = {0xFE, 0x00, 0x00, 0x02, 0x00};
            mysql_packet_write_ok(dr->ps, eof, 5, 0xFE);
        }
        dr->started = true;
    }

    /* Send a data row. */
    {
        StringInfoData rowbuf;
        initStringInfo(&rowbuf);

        for (i = 0; i < ncols; i++)
        {
            bool isnull;
            Datum d = slot_getattr(slot, i + 1, &isnull);
            if (isnull)
            {
                appendStringInfoChar(&rowbuf, 0xFB);  /* NULL */
            }
            else
            {
                char *str;
                bool isvarlena;
                Oid typid;
                Oid typoutput;
                FmgrInfo finfo;
                int slen;

                typid = TupleDescAttr(slot->tts_tupleDescriptor, i)->atttypid;
                getTypeOutputInfo(typid, &typoutput, &isvarlena);
                fmgr_info(typoutput, &finfo);
                str = OutputFunctionCall(&finfo, d);
                slen = (int) strlen(str);
                /* Length-encoded string */
                if (slen < 251)
                {
                    appendStringInfoChar(&rowbuf, (char) slen);
                }
                else if (slen < 65536)
                {
                    appendStringInfoChar(&rowbuf, 0xFC);
                    appendStringInfoChar(&rowbuf, (char)(slen & 0xFF));
                    appendStringInfoChar(&rowbuf, (char)((slen >> 8) & 0xFF));
                }
                else
                {
                    appendStringInfoChar(&rowbuf, 0xFD);
                    appendStringInfoChar(&rowbuf, (char)(slen & 0xFF));
                    appendStringInfoChar(&rowbuf, (char)((slen >> 8) & 0xFF));
                    appendStringInfoChar(&rowbuf, (char)((slen >> 16) & 0xFF));
                }
                appendBinaryStringInfo(&rowbuf, str, slen);
                pfree(str);
            }
        }

        mysql_packet_write_ok(dr->ps, rowbuf.data, rowbuf.len, 0x00);
        pfree(rowbuf.data);
    }

    return true;
}

static void
mysDR_rStartup(DestReceiver *self, int operation, TupleDesc typeinfo)
{
    MysDRState *dr = (MysDRState *) self;
    dr->ncols = typeinfo->natts;
    dr->started = false;
}

static void
mysDR_rShutdown(DestReceiver *self)
{
    MysDRState *dr = (MysDRState *) self;
    /*
     * Do NOT send EOF here.  The protocol-level completion packet
     * (EOF for SELECT, OK for INSERT/UPDATE/DELETE) is the responsibility
     * of mysql_end_command(), mirroring openHalo's endCommand.
     * Sending a packet here would duplicate the end_command packet and
     * confuse the client's protocol state machine.
     */
    (void) dr;
}

static void
mysDR_rDestroy(DestReceiver *self)
{
    pfree(self);
}

static DestReceiver *
mysql_create_dest_receiver(CommandDest dest)
{
    if (dest == DestRemote || dest == DestRemoteExecute ||
        dest == DestRemoteSimple)
    {
        MysDRState *dr = (MysDRState *) palloc0(sizeof(MysDRState));
        dr->pub.receiveSlot = mysDR_receiveSlot;
        dr->pub.rStartup = mysDR_rStartup;
        dr->pub.rShutdown = mysDR_rShutdown;
        dr->pub.rDestroy = mysDR_rDestroy;
        dr->pub.mydest = dest;
        dr->ps = mysql_ps();
        return (DestReceiver *) dr;
    }
    return standard_CreateDestReceiver(dest);
}

static void
mysql_end_command(const QueryCompletion *qc,
                  CommandDest dest,
                  bool force_undecorated_output)
{
    if (dest == DestRemote || dest == DestRemoteExecute ||
        dest == DestRemoteSimple)
    {
        CommandTag  tag = qc->commandTag;
        uint32      caps = mysql_negotiated_caps(mysql_ps());

        /*
         * Mirror openHalo's endCommand: SELECT → EOF, DML → OK.
         * The DestReceiver (mysDR_rShutdown) does NOT send the final
         * completion packet; we own it here.
         */
        if (tag == CMDTAG_SELECT)
        {
            if (caps & MYSQL_CAP_DEPRECATE_EOF)
            {
                /*
                 * DEPRECATE_EOF OK packet: 0xFE header + lenenc
                 * affected_rows=0 + last_insert_id=0 + status_flags
                 * + warning_count=0 + optional info string.
                 * MUST be >= 9 bytes payload so that mysql CLI 8.4
                 * distinguishes it from a size-8 lenenc integer (the
                 * common is_eof_packet() check is "len < 9").
                 */
                char ok[16];
                int  pos = 0;
                ok[pos++] = 0xFE;                    /* OK packet marker */
                ok[pos++] = 0x00;                    /* affected_rows (lenenc 0) */
                ok[pos++] = 0x00;                    /* last_insert_id (lenenc 0) */
                ok[pos++] = 0x02; ok[pos++] = 0x00;  /* status: autocommit */
                ok[pos++] = 0x00; ok[pos++] = 0x00;  /* warnings: 0 */
                ok[pos++] = 0x01; ok[pos++] = 0x20;  /* info: lenenc " " string (2 bytes to reach 9) */
                mysql_packet_write_ok(mysql_ps(), ok, (size_t) pos, 0xFE);
            }
            else
            {
                /* Traditional EOF to mark end of result set. */
                char eof[5] = {0xFE, 0x00, 0x00, 0x02, 0x00};
                mysql_packet_write_ok(mysql_ps(), eof, 5, 0xFE);
            }
        }
        else
        {
            /*
             * Send a MySQL OK packet for INSERT/UPDATE/DELETE and other
             * non-SELECT commands.
             */
            char ok[256];
            int  pos = 0;

            ok[pos++] = 0x00;                    /* OK header */
            ok[pos++] = 0x00;                    /* affected rows = 0 */
            ok[pos++] = 0x00;                    /* last insert id = 0 */
            ok[pos++] = 0x02; ok[pos++] = 0x00;  /* status: autocommit */
            ok[pos++] = 0x00; ok[pos++] = 0x00;  /* warnings: 0 */

            mysql_packet_write_ok(mysql_ps(), ok, (size_t) pos, 0x00);
        }
    }
    else
    {
        standard_EndCommand(qc, dest, force_undecorated_output);
    }
}

static void
mysql_null_command(CommandDest dest)
{
    if (dest == DestRemote || dest == DestRemoteExecute ||
        dest == DestRemoteSimple)
    {
        /* Empty query → MySQL OK. */
        char ok[7];
        int  pos = 0;
        ok[pos++] = 0x00;
        ok[pos++] = 0x00;
        ok[pos++] = 0x00;
        ok[pos++] = 0x02; ok[pos++] = 0x00;
        ok[pos++] = 0x00; ok[pos++] = 0x00;
        mysql_packet_write_ok(mysql_ps(), ok, (size_t) pos, 0x00);
    }
    else
    {
        standard_NullCommand(dest);
    }
}

static void
mysql_send_ready_for_query(CommandDest dest)
{
    /*
     * MySQL protocol has no explicit "ready for query" packet.  The auth
     * OK (sent by the authenticate callback) and the query-completion OK
     * (sent by end_command) already serve as implicit ready signals.
     *
     * We still flush the output buffer to make sure all pending writes
     * reach the client before the backend blocks on the next read.
     */
    if (dest == DestRemote || dest == DestRemoteExecute ||
        dest == DestRemoteSimple)
    {
        pq_flush();
    }
    else
    {
        standard_ReadyForQuery(dest);
    }
}

/* ----------------------------------------------------------------
 *    Error / GUC callbacks
 * ----------------------------------------------------------------
 */
static void
mysql_send_error(ErrorData *edata)
{
    uint16      errcode;
    const char *sqlstate;

    /* Map PG error codes to MySQL-compatible codes. */
    switch (edata->sqlerrcode)
    {
    case ERRCODE_INSUFFICIENT_PRIVILEGE:
        errcode = 1045;
        sqlstate = "28000";
        break;
    case ERRCODE_UNDEFINED_TABLE:
        errcode = 1146;
        sqlstate = "42S02";
        break;
    case ERRCODE_UNDEFINED_COLUMN:
        errcode = 1054;
        sqlstate = "42S22";
        break;
    case ERRCODE_DUPLICATE_TABLE:
        errcode = 1050;
        sqlstate = "42S01";
        break;
    case ERRCODE_SYNTAX_ERROR:
        errcode = 1064;
        sqlstate = "42000";
        break;
    default:
        errcode = 1105;         /* ER_UNKNOWN_ERROR */
        sqlstate = "HY000";
        break;
    }

    mysql_packet_write_err(mysql_ps(), errcode, sqlstate,
                           "%s", edata->message);
}

static void
mysql_report_parameter_status(const char *name, const char *value)
{
    /*
     * MySQL clients do not expect PostgreSQL ParameterStatus messages
     * ('S' packets).  Silently drop them.  In future we may translate
     * selected GUC reports into MySQL session-track messages.
     */
}

/* ----------------------------------------------------------------
 *    ProtocolRoutine instance
 * ----------------------------------------------------------------
 */
static const ProtocolRoutine MySQLProtocolRoutine = {
    .kind = COMPAT_PROTOCOL_MYSQL,
    .name = "MySQL",

    .init = mysql_init,
    .startup_exchange = mysql_startup_exchange,
    .authenticate = mysql_authenticate,
    .mainfunc = NULL,               /* use standard PostgresMain loop  */

    .read_command = mysql_read_command_cb,
    .process_command = mysql_process_command,
    .comm_reset = mysql_comm_reset,
    .is_reading_msg = mysql_is_reading_msg,

    .session_initialize = mysql_session_initialize_noop,
    .send_backend_key_data = mysql_send_backend_key_data_noop,

    .create_dest_receiver = mysql_create_dest_receiver,
    .set_remote_dest_receiver_params = mysql_set_remote_dest_receiver_params,
    .end_command = mysql_end_command,
    .null_command = mysql_null_command,
    .send_ready_for_query = mysql_send_ready_for_query,

    .send_error = mysql_send_error,
    .report_parameter_status = mysql_report_parameter_status,

    .parser_routine = &MySQLParserRoutine,
};

/* ----------------------------------------------------------------
 *    Registration (called at postmaster startup)
 * ----------------------------------------------------------------
 */
void
InitMySQLProtocolRoutine(void)
{
    RegisterProtocolRoutine(&MySQLProtocolRoutine);
}

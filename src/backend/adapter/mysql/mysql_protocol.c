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
#include "libpq/libpq-be.h"
#include "libpq/libpq.h"
#include "miscadmin.h"
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

    ps = mysql_packet_create(port);
    port->protocol_state = (void *) ps;
}

static int
mysql_startup_exchange(Port *port)
{
    MysPacketState *ps = (MysPacketState *) port->protocol_state;
    int            status;

    ereport(LOG, (errmsg("MySQL: startup_exchange begin")));
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
        /*
         * M1 fast path: intercept simple queries that the mysql CLI sends
         * during its init handshake.  Respond with pre-built MySQL text
         * protocol packets to keep the client happy.
         */
        if (inBuf->len > 0)
        {
            const char *sql = inBuf->data;
            /* mysql 8.4.10 init probes — respond inline */
            if (strncmp(sql, "select @@version_comment", 24) == 0 ||
                strncmp(sql, "select @@version", 15) == 0 ||
                strncmp(sql, "SELECT @@version_comment", 24) == 0 ||
                strncmp(sql, "SELECT @@version", 15) == 0)
            {
                char colcnt, coldef[52], row[32], eof[5] = {0xFE,0x00,0x00,0x02,0x00};
                /* column count: lenenc(1) */
                colcnt = 1;
                mysql_packet_write_ok(mysql_ps(), &colcnt, 1, 0x00);
                /* column definition (lenenc_str for all string fields) */
                memcpy(coldef, "\x03""def\0\0\0\x0f""version_comment\x0f""version_comment\x0c\x2D\0", 40);
                memset(coldef+40, 0, 4); coldef[40] = 30; /* col len = 30 */
                coldef[44] = 253; /* MYSQL_TYPE_VAR_STRING */
                memset(coldef+45, 0, 7); /* flags(2)=0, decimals(1)=0, filler(2)=0 */
                mysql_packet_write_ok(mysql_ps(), coldef, 52, 0x00);
                mysql_packet_write_ok(mysql_ps(), eof, 5, 0xFE);
                /* row: lenenc(30) + '8.0.40-openhalo-1.0' */
                memset(row, 0, sizeof(row));
                row[0] = 30;
                memcpy(row + 1, "8.0.40-openhalo-1.0", 22);
                mysql_packet_write_ok(mysql_ps(), row, 31, 0x00);
                mysql_packet_write_ok(mysql_ps(), eof, 5, 0xFE);
                return PROTOCOL_COMMAND_HANDLED;
            }
            if (strncmp(sql, "SELECT 1", 8) == 0 ||
                strncmp(sql, "select 1", 8) == 0)
            {
                char colcnt = 1;
                char cdef[28], row[3], eof[5] = {0xFE,0x00,0x00,0x02,0x00};
                mysql_packet_write_ok(mysql_ps(), &colcnt, 1, 0x00);
                /* column definition for "1": lenenc_str "def", catalog, schema, table, org_table, col_name, org_col_name, then fixed fields */
                memcpy(cdef, "\x03""def\0\0\0\x01""1\x01""1\x0c\x2d\0", 17);
                memset(cdef+17, 0, 4); cdef[17] = 1; /* col len */
                cdef[21] = 8; /* MYSQL_TYPE_LONGLONG */
                memset(cdef+22, 0, 6);
                mysql_packet_write_ok(mysql_ps(), cdef, 28, 0x00);
                mysql_packet_write_ok(mysql_ps(), eof, 5, 0xFE);
                /* row: lenenc(1) + '1' */
                row[0] = 1; row[1] = '1';
                mysql_packet_write_ok(mysql_ps(), row, 2, 0x00);
                mysql_packet_write_ok(mysql_ps(), eof, 5, 0xFE);
                return PROTOCOL_COMMAND_HANDLED;
            }
        }
        /* Fall through: map to PG Query message type for standard execution. */
        *command = 'Q';
        return PROTOCOL_COMMAND_PASSTHROUGH;

    case MYSQL_PSEUDO_QUIT:
        *command = 'X';
        return PROTOCOL_COMMAND_PASSTHROUGH;

    case MYSQL_PSEUDO_PING:
        /* Send immediate OK, skip the main loop. */
        {
            char ok[7];
            int  pos = 0;
            ok[pos++] = 0x00;
            ok[pos++] = 0x00;
            ok[pos++] = 0x00;
            ok[pos++] = 0x02; ok[pos++] = 0x00;
            ok[pos++] = 0x00; ok[pos++] = 0x00;
            mysql_packet_write_ok(mysql_ps(), ok, (size_t) pos, 0x00);
        }
        return PROTOCOL_COMMAND_HANDLED;

    default:
        return PROTOCOL_COMMAND_PASSTHROUGH;
    }
}

static void
mysql_comm_reset(void)
{
    mysql_packet_reset_seq(mysql_ps());
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
     * M1 reuses the standard PG tuple receiver (printtup).  Delegate to
     * the standard setup so that the receiver gets portal parameters.
     */
    SetRemoteDestReceiverParams(receiver, portal);
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
        /* Send column count as a length-encoded integer. */
        {
            char colcnt[16];
            int  pos = 0;
            if (ncols < 251)
            {
                colcnt[pos++] = (char) ncols;
            }
            else if (ncols < 65536)
            {
                colcnt[pos++] = (char) 0xFC;
                colcnt[pos++] = (char) (ncols & 0xFF);
                colcnt[pos++] = (char) ((ncols >> 8) & 0xFF);
            }
            else
            {
                colcnt[pos++] = (char) 0xFD;
                colcnt[pos++] = (char) (ncols & 0xFF);
                colcnt[pos++] = (char) ((ncols >> 8) & 0xFF);
                colcnt[pos++] = (char) ((ncols >> 16) & 0xFF);
            }
            mysql_packet_write_ok(dr->ps, colcnt, (size_t) pos, 0x00);
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
        /* EOF after column definitions. */
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
    /* Send EOF after all rows. */
    char eof[5] = {0xFE, 0x00, 0x00, 0x02, 0x00};
    mysql_packet_write_ok(dr->ps, eof, 5, 0xFE);
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
        char        completionTag[COMPLETION_TAG_BUFSIZE];
        Size        len;
        const char *tag;

        len = BuildQueryCompletionString(completionTag, qc,
                                          force_undecorated_output);
        tag = (len > 0) ? completionTag : NULL;

        /*
         * Send a MySQL OK packet with the command tag as the info field.
         * For M1 we use a minimal OK: affected_rows=0, last_insert_id=0,
         * status=autocommit, warnings=0.
         *
         * The protocol expects: <OK header> <affected_rows(lenenc)>
         * <last_insert_id(lenenc)> <status(2)> <warnings(2)>
         * [<info(string)> if status & SERVER_SESSION_STATE_CHANGED]
         *
         * For simplicity in M1, send a minimal OK.  Proper affected_rows
         * / last_insert_id / info are deferred to M2.
         */
        {
            char ok[256];
            int  pos = 0;

            ok[pos++] = 0x00;                    /* OK header */
            ok[pos++] = 0x00;                    /* affected rows = 0 */
            ok[pos++] = 0x00;                    /* last insert id = 0 */
            ok[pos++] = 0x02; ok[pos++] = 0x00;  /* status: autocommit */
            ok[pos++] = 0x00; ok[pos++] = 0x00;  /* warnings: 0 */

            /* If we have a tag, append it as info (lenenc string). */
            if (tag != NULL && len > 0)
            {
                ok[pos++] = (char) (len & 0xFF);  /* length-encoded string */
                memcpy(ok + pos, tag, len);
                pos += (int) len;
            }

            mysql_packet_write_ok(mysql_ps(), ok, (size_t) pos, 0x00);
        }
    }
    else
    {
        /* Non-remote dest: delegate to standard PG behavior. */
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
     * For non-remote destinations, delegate to the standard PG path.
     */
    if (dest != DestRemote && dest != DestRemoteExecute &&
        dest != DestRemoteSimple)
        standard_ReadyForQuery(dest);
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

    .parser_routine = NULL,         /* standard PG parser for M1             */
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

/*-------------------------------------------------------------------------
 *
 * mysql_command.c
 *    MySQL COM command read and dispatch for the ProtocolRoutine
 *    read_command / process_command callbacks.
 *
 * The read_command callback reads a COM packet off the wire and converts
 * it into a pseudo "firstchar" value that the PostgresMain switch loop
 * already understands (PqMsg_Query / PqMsg_Quit / …).  This avoids
 * rewriting the main loop for MySQL.
 *
 * COM_QUERY and COM_INIT_DB are mapped to PqMsg_Query after prepending
 * appropriate lowering.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/adapter/mysql/mysql_command.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "adapter/mysql/mysql_command.h"
#include "adapter/mysql/mysql_packet.h"
#include "libpq/libpq.h"
#include "libpq/libpq-be.h"
#include "miscadmin.h"
#include "postmaster/protocol_routine.h"
#include "utils/elog.h"

#include <string.h>

/* ----------------------------------------------------------------
 *    mysql_read_command
 *
 * Read one MySQL COM packet and convert it into a pseudo PG wire
 * message type stored in *command, with text payload in inBuf.
 *
 * Returns the byte count of the first packet payload, or -1 on EOF.
 * ----------------------------------------------------------------
 */
int
mysql_read_command(MysPacketState *ps, int *command, StringInfo inBuf)
{
    char       *payload;
    size_t      len;
    uint8       com;

    if (!mysql_packet_read(ps, &payload, &len))
        return -1;

    if (len < 1)
    {
        /* Empty packet — treat as an empty COM_QUERY. */
        pfree(payload);
        *command = MYSQL_PSEUDO_QUERY;
        resetStringInfo(inBuf);
        return 0;
    }

    com = (uint8) payload[0];

    switch (com)
    {
    case COM_QUERY:
        *command = MYSQL_PSEUDO_QUERY;
        /*
         * Pass the SQL text (after the 1-byte command code).
         * The PG protocol expects a NUL-terminated string and pq_getmsgend()
         * checks cursor == len after pq_getmsgstring() reads it.  We must
         * include the NUL in the length so that the end-of-message check
         * succeeds.
         */
        resetStringInfo(inBuf);
        if (len > 1)
        {
            /*
             * Pass the SQL text through unchanged.  mysql_process_command()
             * handles init probes (SELECT 1, @@version_comment) inline with
             * pre-built MySQL packets.  DestReceiver path will be fixed
             * separately for arbitrary queries.
             */
            appendBinaryStringInfo(inBuf, payload + 1, (int)(len - 1));
        }
        /* Include the trailing NUL in the buffer length. */
        enlargeStringInfo(inBuf, 1);
        inBuf->data[inBuf->len] = '\0';
        inBuf->len++;
        break;

    case COM_INIT_DB:
        /* COM_INIT_DB: convert "USE <db>" into a Query for processing. */
        *command = MYSQL_PSEUDO_QUERY;
        resetStringInfo(inBuf);
        if (len > 1)
        {
            char *dbname = pnstrdup(payload + 1, (int)(len - 1));
            appendStringInfo(inBuf, "USE `%s`", dbname);
            pfree(dbname);
        }
        break;

    case COM_QUIT:
        *command = MYSQL_PSEUDO_QUIT;
        resetStringInfo(inBuf);
        break;

    case COM_PING:
        *command = MYSQL_PSEUDO_PING;
        resetStringInfo(inBuf);
        break;

    case COM_FIELD_LIST:
        /* Not supported in M1; return an error that will be caught later. */
        *command = MYSQL_PSEUDO_QUERY;
        resetStringInfo(inBuf);
        appendStringInfoString(inBuf, "KILL CONNECTION 0");  /* dummy */
        ereport(WARNING,
                (errmsg("COM_FIELD_LIST is not supported in M1")));
        break;

    default:
        ereport(COMMERROR,
                (errmsg("unsupported MySQL COM command 0x%02x", com)));
        pfree(payload);
        return -1;
    }

    pfree(payload);
    return (int) len;
}

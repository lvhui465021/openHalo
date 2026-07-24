/*-------------------------------------------------------------------------
 *
 * mysql_command.h
 *    MySQL COM command dispatch for the read-command / process-command
 *    ProtocolRoutine callbacks.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/adapter/mysql/mysql_command.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef MYSQL_COMMAND_H
#define MYSQL_COMMAND_H

#include "libpq/libpq-be.h"

/* MySQL COM command codes (subset used in M1). */
#define COM_SLEEP               0x00
#define COM_QUIT                0x01
#define COM_INIT_DB             0x02
#define COM_QUERY               0x03
#define COM_FIELD_LIST          0x04
#define COM_PING                0x0E

/* Internal representation passed from read_command to process_command. */
#define MYSQL_PSEUDO_QUERY      0x03    /* mapped to PqMsg_Query   */
#define MYSQL_PSEUDO_QUIT       'X'     /* mapped to PqMsg_Quit   */
#define MYSQL_PSEUDO_PING       'Y'     /* immediate OK response  */

struct MysPacketState;

/*
 * Read one MySQL command from the socket, assembling split packets.
 * The decoded command is written to *command and the text (if any) is
 * placed in inBuf.  Returns the packet sequence number of the first
 * packet, or -1 on EOF.
 */
extern int  mysql_read_command(struct MysPacketState *ps,
                               int *command, StringInfo inBuf);

#endif   /* MYSQL_COMMAND_H */

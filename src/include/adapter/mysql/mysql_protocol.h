/*-------------------------------------------------------------------------
 *
 * mysql_protocol.h
 *    Declaration for the MySQL ProtocolRoutine registration function.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/adapter/mysql/mysql_protocol.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef MYSQL_PROTOCOL_H
#define MYSQL_PROTOCOL_H

extern void InitMySQLProtocolRoutine(void);
extern const struct ProtocolRoutine MySQLProtocolRoutine;

#endif   /* MYSQL_PROTOCOL_H */

/*-------------------------------------------------------------------------
 *
 * mysql_packet.h
 *    MySQL packet-layer I/O for the compatibility adapter.
 *
 * The MySQL wire protocol wraps every payload in a 4-byte header:
 *    [3 bytes little-endian payload length][1 byte sequence number]
 *
 * Sequence numbers start at 0 for the greeting and increment per-packet
 * on both the client→server and server→client directions independently.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/adapter/mysql/mysql_packet.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef MYSQL_PACKET_H
#define MYSQL_PACKET_H

#include "libpq/libpq-be.h"

/* Maximum payload bytes in a single MySQL packet (2^24 - 1). */
#define MYSQL_PACKET_HEADER_SIZE     4
#define MYSQL_MAX_PAYLOAD_LENGTH     ((1 << 24) - 1)

/*
 * Opaque handle for MySQL packet-layer state (sequence counter, write buffer).
 */
typedef struct MysPacketState MysPacketState;

/* Create a packet-layer handle bound to the given Port. */
extern MysPacketState *mysql_packet_create(Port *port);

/* Release all resources without flushing. */
extern void mysql_packet_free(MysPacketState *ps);

/* --- raw I/O (used during the startup exchange) -------------------- */

/* Read exactly one MySQL packet payload into a freshly palloc'd buffer.
 * *payload receives the buffer, *len the number of payload bytes.
 * Returns true on success; on EOF or protocol error the caller must
 * close the connection (we ereport a SQL-facing error). */
extern bool mysql_packet_read(MysPacketState *ps,
                              char **payload, size_t *len);

/* Write a single-packet payload + flush.  seq is reset on first write. */
extern void mysql_packet_write(MysPacketState *ps,
                               const char *payload, size_t len);

/* Write + flush an OK/EOF packet (header byte 0x00 or 0xFE). */
extern void mysql_packet_write_ok(MysPacketState *ps,
                                  const char *payload, size_t len,
                                  uint8 header);

/* Write + flush an ERR packet (header byte 0xFF). */
extern void mysql_packet_write_err(MysPacketState *ps,
                                   uint16 errcode,
                                   const char *sqlstate,
                                   const char *fmt, ...)
            pg_attribute_printf(4, 5);

/* Reset client sequence-number tracking (called on error recovery). */
extern void mysql_packet_reset_seq(MysPacketState *ps);

/* Set the server sequence number for the next outgoing packet. */
extern void mysql_packet_set_server_seq(MysPacketState *ps, uint8 seq);

/* Store / retrieve opaque per-connection auth state. */
extern void mysql_packet_set_auth_state(MysPacketState *ps, void *state);
extern void *mysql_packet_get_auth_state(MysPacketState *ps);

#endif   /* MYSQL_PACKET_H */

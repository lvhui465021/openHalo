/*-------------------------------------------------------------------------
 *
 * protocol_routine.h
 *    Protocol-routine dispatch interface for multi-protocol backends.
 *
 * A ProtocolRoutine is a vtable of callbacks that let a wire protocol
 * (PostgreSQL, MySQL, TDS, …) plug into the backend lifecycle at the
 * connection-init, command-I/O, session, and DestReceiver layers.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/postmaster/protocol_routine.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PROTOCOL_ROUTINE_H
#define PROTOCOL_ROUTINE_H

#include "libpq/libpq-be.h"          /* CompatibilityProtocolKind, Port        */
#include "tcop/dest.h"               /* CommandDest, DestReceiver             */
#include "tcop/utility.h"            /* ProcessUtility_hook_type               */

/* forward declarations */
struct QueryCompletion;
struct ParserRoutine;
struct PortalData;
struct ErrorData;
struct Node;

/* ----------------------------------------------------------------
 *    ProtocolCommandResult
 *
 * Returned by process_command():
 *   PASSTHROUGH  – caller should handle the command via standard path
 *   HANDLED      – protocol consumed the command; skip standard handling
 * ----------------------------------------------------------------
 */
typedef enum ProtocolCommandResult
{
    PROTOCOL_COMMAND_PASSTHROUGH,
    PROTOCOL_COMMAND_HANDLED
} ProtocolCommandResult;

/* ----------------------------------------------------------------
 *    ProtocolRoutine
 *
 * Each wire protocol provides one const instance of this struct.
 * A NULL callback means "use the standard PostgreSQL behaviour".
 * ----------------------------------------------------------------
 */
typedef struct ProtocolRoutine
{
    CompatibilityProtocolKind kind;
    const char *name;                  /* human-readable, for error messages  */

    /* --- lifecycle hooks (called during backend startup) --- */
    void        (*init)(Port *port);
    int         (*startup_exchange)(Port *port);   /* 0 = ok, -1 = reject   */
    void        (*mainfunc)(Port *port);

    /* --- command I/O hooks --- */
    int         (*read_command)(StringInfo inBuf);
    ProtocolCommandResult (*process_command)(int *command, StringInfo inBuf);
    void        (*comm_reset)(void);
    bool        (*is_reading_msg)(void);

    /* --- session hooks --- */
    void        (*session_initialize)(Port *port);
    void        (*send_backend_key_data)(int pid, const uint8 *key, int keylen);

    /* --- DestReceiver hooks --- */
    DestReceiver *(*create_dest_receiver)(CommandDest dest);
    void        (*set_remote_dest_receiver_params)(DestReceiver *receiver,
                                                    struct PortalData *portal);
    void        (*end_command)(const QueryCompletion *qc,
                                CommandDest dest,
                                bool force_undecorated_output);
    void        (*null_command)(CommandDest dest);
    void        (*send_ready_for_query)(CommandDest dest);

    /* --- simple-query multi-statement policy / result framing --- */
    bool        (*allow_multi_statements)(void);
    bool        (*simple_query_statement_ends_xact)(void);
    void        (*set_simple_query_more_results)(bool more);
    void        (*before_simple_query_statement)(struct Node *stmt);

    /* --- error / GUC hooks --- */
    void        (*send_error)(struct ErrorData *edata);
    void        (*report_parameter_status)(const char *name, const char *value);

    /* --- utility-command execution --- */
    ProcessUtility_hook_type process_utility;

    /* --- parser selection --- */
    const struct ParserRoutine *parser_routine;

    /* --- authentication hook --- */
    void        (*authenticate)(Port *port);
} ProtocolRoutine;

/* ----------------------------------------------------------------
 *    Global registry and accessors
 * ----------------------------------------------------------------
 */
extern const ProtocolRoutine *GetCurrentProtocolRoutine(void);
extern const ProtocolRoutine *GetProtocolRoutine(CompatibilityProtocolKind kind);
extern void   AssignProtocolRoutine(Port *port);
extern void   RegisterProtocolRoutine(const ProtocolRoutine *routine);
extern bool   CompatibilityProtocolKindIsValid(CompatibilityProtocolKind kind);

/* ----------------------------------------------------------------
 *    Helper functions called from postgres.c / dest.c
 * ----------------------------------------------------------------
 */
extern void ProtocolSetRemoteDestReceiverParams(DestReceiver *receiver,
                                                struct PortalData *portal);

#endif   /* PROTOCOL_ROUTINE_H */

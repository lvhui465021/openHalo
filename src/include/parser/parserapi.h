/*-------------------------------------------------------------------------
 *
 * parserapi.h
 *    ParserRoutine interface for multi-dialect SQL parsing.
 *
 * A ParserRoutine provides dialect-specific raw-parse and expression-
 * transform callbacks.  It is selected per-session through the protocol
 * layer (ProtocolRoutine.parser_routine) and stored in ParseState so
 * that sub-queries inherit the same dialect.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/parserapi.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PARSERAPI_H
#define PARSERAPI_H

#include "nodes/pg_list.h"
#include "parser/parser.h"          /* RawParseMode, raw_parser declaration */

/* forward declaration */
struct ParseState;

/* ----------------------------------------------------------------
 *    ParserRoutine
 *
 * Each SQL dialect provides one const instance.  Callbacks that are
 * NULL are treated as "not applicable for this dialect" and the
 * standard PostgreSQL implementation is used instead.
 * ----------------------------------------------------------------
 */
typedef struct ParserRoutine
{
    /*
     * raw_parse  –  convert a SQL string into a List of RawStmt nodes.
     * Equivalent to raw_parser() but may use a dialect-specific scanner
     * and grammar.
     */
    List       *(*raw_parse)(const char *str, RawParseMode mode);

    /*
     * transform_expr_node  –  optional hook for transforming dialect-
     * specific raw expression nodes (e.g. UserVarRef, UserVarAssign)
     * before the standard expression transformer processes them.
     *
     * Return true if the node was fully transformed (result is set).
     * Return false to let the standard switch handle it.
     */
    bool        (*transform_expr_node)(struct ParseState *pstate,
                                       Node *expr,
                                       Node **result);

    /* --- reserved for future dialect-specific callbacks --- */
    /*  e.g. transformStmt, transformSelectStmt, …            */
} ParserRoutine;

#endif   /* PARSERAPI_H */

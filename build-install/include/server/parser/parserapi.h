/*-------------------------------------------------------------------------
 *
 * parserapi.h
 *    ParserRoutine interface for multi-dialect SQL parsing.
 *
 * A ParserRoutine provides dialect-specific callbacks for raw parsing,
 * semantic analysis, expression transformation, function resolution,
 * and utility-command handling.  It is selected per-session through the
 * protocol layer (ProtocolRoutine.parser_routine) and stored in
 * ParseState so that sub-queries inherit the same dialect.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/parserapi.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PARSERAPI_H
#define PARSERAPI_H

#include "common/kwlookup.h"        /* ScanKeywordList */
#include "nodes/pg_list.h"
#include "parser/parse_func.h"      /* FuncDetailCode */
#include "parser/parser.h"          /* RawParseMode, raw_parser declaration */

/* forward declarations */
struct AlterTableStmt;
struct CallStmt;
struct CreateStmt;
struct DeleteStmt;
struct FuncCall;
struct InsertStmt;
struct OnConflictClause;
struct ParseState;
struct SelectStmt;
struct UpdateStmt;

/* ----------------------------------------------------------------
 *    ParserRoutine
 *
 * Each SQL dialect provides one const instance.  Callbacks that are
 * NULL are treated as "use the standard PostgreSQL implementation".
 * ----------------------------------------------------------------
 */
typedef struct ParserRoutine
{
    /* ------------------------------------------------------------
     * Keyword table pointers  --  dialect-specific scanner keyword
     * list, token mapping, and category mapping.  NULL means the
     * standard PostgreSQL keyword table is used.
     * ------------------------------------------------------------
     */
    const ScanKeywordList     *keywordlist;
    const uint16              *keyword_tokens;
    const uint8               *keyword_categories;

    /* ------------------------------------------------------------
     * Raw parsing
     * ------------------------------------------------------------
     */

    /*
     * raw_parse  –  convert a SQL string into a List of RawStmt nodes.
     * Equivalent to raw_parser() but may use a dialect-specific scanner
     * and grammar.
     */
    List       *(*raw_parse)(const char *str, RawParseMode mode);

    /* ------------------------------------------------------------
     * Statement-level transform hooks.
     * Each returns a Query*.  NULL means use standard
     * transformTopLevelStmt / transformStmt.
     * ------------------------------------------------------------
     */
    Query      *(*transformStmt)(struct ParseState *pstate, Node *parseTree);
    Query      *(*transformSelectStmt)(struct ParseState *pstate,
                                       struct SelectStmt *stmt);
    Query      *(*transformInsertStmt)(struct ParseState *pstate,
                                       struct InsertStmt *stmt);
    Query      *(*transformUpdateStmt)(struct ParseState *pstate,
                                       struct UpdateStmt *stmt);
    Query      *(*transformDeleteStmt)(struct ParseState *pstate,
                                       struct DeleteStmt *stmt);
    Query      *(*transformCallStmt)(struct ParseState *pstate,
                                     struct CallStmt *stmt);
    Query      *(*transformOptionalSelectInto)(struct ParseState *pstate,
                                               Node *parseTree);
    Query      *(*transformSetOperationStmt)(struct ParseState *pstate,
                                             struct SelectStmt *stmt);
    Node       *(*transformSetOperationTree)(struct ParseState *pstate,
                                             struct SelectStmt *stmt,
                                             bool isTopLevel,
                                             List **targetlist);

    /*
     * analyze_requires_snapshot  --  return true if the raw parse tree
     * requires a transaction snapshot for analysis (e.g. DML).
     */
    bool        (*analyze_requires_snapshot)(RawStmt *parseTree);

    /* ------------------------------------------------------------
     * Clause-level transform hooks.
     * ------------------------------------------------------------
     */
    void        (*transformOnConflictArbiter)(struct ParseState *pstate,
                                              struct OnConflictClause *onConflictClause,
                                              List **arbiterExpr,
                                              Node **arbiterWhere,
                                              Oid *constraint);
    List       *(*transformGroupClause)(struct ParseState *pstate,
                                        List *grouplist,
                                        List **groupingSets,
                                        List **targetlist,
                                        List *sortClause,
                                        ParseExprKind exprKind,
                                        bool useSQL99);
    List       *(*transformDistinctClause)(struct ParseState *pstate,
                                           List **targetlist,
                                           List *sortClause,
                                           bool is_agg);

    /* ------------------------------------------------------------
     * Expression transform hook.
     * ------------------------------------------------------------
     */
    Node       *(*transformExpr)(struct ParseState *pstate,
                                 Node *expr,
                                 ParseExprKind exprKind);

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

    /* ------------------------------------------------------------
     * Utility command transform hooks.
     * ------------------------------------------------------------
     */
    List       *(*transformCreateStmt)(struct CreateStmt *stmt,
                                       const char *queryString);
    struct AlterTableStmt *
                (*transformAlterTableStmt)(Oid relid,
                                           struct AlterTableStmt *stmt,
                                           const char *queryString,
                                           List **beforeStmts,
                                           List **afterStmts);

    /* ------------------------------------------------------------
     * Function / expression resolution.
     * ------------------------------------------------------------
     */
    Node       *(*ParseFuncOrColumn)(struct ParseState *pstate,
                                     List *funcname,
                                     List *fargs,
                                     Node *last_srf,
                                     struct FuncCall *fn,
                                     bool proc_call,
                                     int location);
    void        (*make_fn_arguments)(struct ParseState *pstate,
                                     List *fargs,
                                     Oid *actual_arg_types,
                                     Oid *declared_arg_types);
    FuncDetailCode (*func_get_detail)(List *funcname,
                                      List *fargs,
                                      List *fargnames,
                                      int nargs,
                                      Oid *argtypes,
                                      bool expand_variadic,
                                      bool expand_defaults,
                                      bool include_out_arguments,
                                      Oid *funcid,
                                      Oid *rettype,
                                      bool *retset,
                                      int *nvargs,
                                      Oid *vatype,
                                      Oid **true_typeids,
                                      List **argdefaults);
} ParserRoutine;

#endif   /* PARSERAPI_H */

/*-------------------------------------------------------------------------
 *
 * mys_analyze.h
 *    MySQL parser support declarations.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/mysql/mys_analyze.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef MYS_ANALYZE_H
#define MYS_ANALYZE_H

#include "parser/parse_node.h"

Query *mys_transformOptionalSelectInto(ParseState *pstate, Node *parseTree);
Query *mys_transformStmt(ParseState *pstate, Node *parseTree);
Query *mys_transformSelectStmt(ParseState *pstate, SelectStmt *stmt);
Query *mys_transformInsertStmt(ParseState *pstate, InsertStmt *stmt);
Query *mys_transformDeleteStmt(ParseState *pstate, DeleteStmt *stmt);
Query *mys_transformUpdateStmt(ParseState *pstate, UpdateStmt *stmt);
Query *mys_transformCallStmt(ParseState *pstate, CallStmt *stmt);
Query *mys_transformSetOperationStmt(ParseState *pstate, SelectStmt *stmt);
Node *mys_transformSetOperationTree(ParseState *pstate, 
                                    SelectStmt *stmt, 
                                    bool isTopLevel, 
                                    List **targetlist);
bool mys_stmt_requires_parse_analysis(RawStmt *parseTree);
bool mys_analyze_requires_snapshot(RawStmt *parseTree);

#endif							/* MYS_ANALYZE_H */


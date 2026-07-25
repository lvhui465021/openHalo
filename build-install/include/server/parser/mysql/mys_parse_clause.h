/*-------------------------------------------------------------------------
 *
 * mys_parse_clause.h
 *    MySQL parser support declarations.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/mysql/mys_parse_clause.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef MYS_PARSE_CLAUSE_H
#define MYS_PARSE_CLAUSE_H

#include "parser/parse_node.h"


void mys_transformOnConflictArbiter(ParseState *pstate, 
                                    OnConflictClause *onConflictClause, 
                                    List **arbiterExpr, 
                                    Node **arbiterWhere, 
                                    Oid *constraint);

List * mys_transformDistinctClause(ParseState *pstate, 
                                   List **targetlist, 
                                   List *sortClause, 
                                   bool is_agg);

List *mys_transformGroupClause(ParseState *pstate, List *grouplist, List **groupingSets,
                               List **targetlist, List *sortClause,
                               ParseExprKind exprKind, bool useSQL99);
						   										   
#endif							/* MYS_PARSE_CLAUSE_H */


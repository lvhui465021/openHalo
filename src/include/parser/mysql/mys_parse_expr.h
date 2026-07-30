/*-------------------------------------------------------------------------
 *
 * mys_parse_expr.h
 *    MySQL parser support declarations.
 *
 * Portions Copyright (c) 2026, HaloLab / openHalo Contributors
 *
 * src/include/parser/mysql/mys_parse_expr.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef MYS_PARSE_EXPR_H
#define MYS_PARSE_EXPR_H

#include "parser/parse_node.h"

extern Node *mys_transformExpr(ParseState *pstate, 
                               Node *expr, 
                               ParseExprKind exprKind);

#endif							/* MYS_PARSE_EXPR_H */


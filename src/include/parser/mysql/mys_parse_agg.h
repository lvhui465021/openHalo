/*-------------------------------------------------------------------------
 *
 * mys_parse_agg.h
 *    MySQL parser support declarations.
 *
 * Portions Copyright (c) 2026, HaloLab / openHalo Contributors
 *
 * src/include/parser/mysql/mys_parse_agg.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef MYS_PARSE_AGG_H
#define MYS_PARSE_AGG_H

void mys_parseCheckAggregates(ParseState *pstate, Query *qry);

#endif							/* MYS_PARSE_AGG_H */


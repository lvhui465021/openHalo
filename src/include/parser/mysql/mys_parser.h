/*-------------------------------------------------------------------------
 *
 * mys_parser.h
 *    Declarations for the MySQL-compatibility parser entry point.
 *
 * The MySQL parser uses its own scanner (mys_scan.l) and grammar
 * (mys_gram.y), independent of the PG standard base_yyparser.  The
 * ParserRoutine.raw_parse callback points to mys_raw_parser().
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/mysql/mys_parser.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef MYS_PARSER_H
#define MYS_PARSER_H

#include "parser/parser.h"

extern List *mys_raw_parser(const char *str, RawParseMode mode);

#endif   /* MYS_PARSER_H */

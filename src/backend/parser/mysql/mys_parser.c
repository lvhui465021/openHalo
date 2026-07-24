/*-------------------------------------------------------------------------
 *
 * mys_parser.c
 *    Entry point for the MySQL-compatibility parser.
 *
 * Initial M2 skeleton: delegates to the standard PG raw_parser() as a
 * pass-through.  The dedicated MySQL scanner (mys_scan.l) and grammar
 * (mys_gram.y) will replace this delegation incrementally, grammar
 * family by grammar family (session/SHOW → minimal DDL → SELECT →
 * INSERT → UPDATE → DELETE → advanced DDL).
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/parser/mysql/mys_parser.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "parser/parser.h"
#include "parser/mysql/mys_parser.h"

/*
 * mys_raw_parser
 *
 * Parse a SQL string using the MySQL-compatibility dialect.
 *
 * M2 initial state: forward to the standard PG raw_parser.  This lets
 * the M1 protocol layer function immediately while the MySQL scanner
 * and grammar are built out incrementally.
 */
List *
mys_raw_parser(const char *str, RawParseMode mode)
{
    return raw_parser(str, mode);
}

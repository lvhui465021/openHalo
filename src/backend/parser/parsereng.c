/*-------------------------------------------------------------------------
 *
 * parsereng.c
 *    Parser engine selection: standard and MySQL routine singletons.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/parser/parsereng.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "parser/parser.h"            /* raw_parser, RawParseMode    */
#include "parser/parserapi.h"         /* ParserRoutine               */
#include "parser/parsereng.h"
#include "parser/mysql/mys_analyze.h"
#include "parser/mysql/mys_parse_clause.h"
#include "parser/mysql/mys_parser.h"  /* mys_raw_parser              */
#include "parser/mysql/mys_expr_transform.h"  /* mys_transform_expr_node */

/* ----------------------------------------------------------------
 *    StandardParserRoutine  –  PG dialect
 * ----------------------------------------------------------------
 */
static const ParserRoutine StandardParserRoutine = {
    .raw_parse = raw_parser,
    .transform_expr_node = NULL,
};

/*
 * MySQLParserRoutine  –  MySQL-compatibility dialect.
 *
 * Initial M2 state: mys_raw_parser delegates to the standard PG
 * raw_parser.  The dedicated MySQL scanner (mys_scan.l) and grammar
 * (mys_gram.y) will replace this delegation incrementally.
 */
const ParserRoutine MySQLParserRoutine = {
	.raw_parse = mys_raw_parser,
	.transformOptionalSelectInto = mys_transformOptionalSelectInto,
	.transformOnConflictArbiter = mys_transformOnConflictArbiter,
    .transform_expr_node = mys_transform_expr_node,
	.figure_colname = mys_figure_colname,
};

const ParserRoutine *
GetStandardParserRoutine(void)
{
    return &StandardParserRoutine;
}

const ParserRoutine *
GetMySQLParserRoutine(void)
{
    return &MySQLParserRoutine;
}

void
InitParserEngine(void)
{
    /* placeholder for future dynamic registration */
}

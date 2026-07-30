/*-------------------------------------------------------------------------
 *
 * parsereng.c
 *    Parser engine selection: standard and MySQL routine singletons.
 *
 * Portions Copyright (c) 2026, HaloLab / openHalo Contributors
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

#include "miscadmin.h"
#include "libpq/libpq-be.h"

/* GUC variable */
int database_compat_mode = POSTGRESQL_COMPAT_MODE;

/* Parser Engine Instance */
const ParserRoutine *parserengine = NULL;

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

/*
 * InitParserEngine
 *
 * Selects the parser engine based on database_compat_mode.
 * When running in MYSQL_COMPAT_MODE with an active MySQL protocol,
 * the MySQL parser engine is installed; otherwise the standard
 * PostgreSQL parser is used.  The switch is extensible: additional
 * compat modes (Oracle, Sybase, etc.) can add their own cases.
 */
void
InitParserEngine(void)
{
	switch (database_compat_mode)
	{
		case POSTGRESQL_COMPAT_MODE:
			parserengine = GetStandardParserRoutine();
			break;

		case MYSQL_COMPAT_MODE:

			if ((MyProcPort != NULL) &&
				(MyProcPort->protocol_kind == COMPAT_PROTOCOL_MYSQL))
			{
				parserengine = GetMySQLParserRoutine();
			}
			else
			{
				parserengine = GetStandardParserRoutine();
			}

			break;

		default:
			parserengine = GetStandardParserRoutine();
			break;
	}
}

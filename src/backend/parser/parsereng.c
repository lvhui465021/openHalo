/*-------------------------------------------------------------------------
 *
 * parsereng.c
 *    Parser engine selection: standard-routine singleton and initialization.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/parser/parsereng.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "parser/parser.h"         /* raw_parser, RawParseMode */
#include "parser/parserapi.h"      /* ParserRoutine            */
#include "parser/parsereng.h"

/* ----------------------------------------------------------------
 *    StandardParserRoutine  –  the singleton for PG dialect
 * ----------------------------------------------------------------
 */
static const ParserRoutine StandardParserRoutine = {
    .raw_parse = raw_parser,
    .transform_expr_node = NULL,
};

const ParserRoutine *
GetStandardParserRoutine(void)
{
    return &StandardParserRoutine;
}

/*
 * InitParserEngine  –  called once during backend startup.
 * Currently a no-op since the standard routine is statically initialized.
 * This is the hook point for future dynamic registration of dialect routines.
 */
void
InitParserEngine(void)
{
    /* placeholder for future initialization */
}

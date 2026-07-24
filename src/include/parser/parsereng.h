/*-------------------------------------------------------------------------
 *
 * parsereng.h
 *    Parser engine selection and initialization.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/parsereng.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PARSERENG_H
#define PARSERENG_H

#include "parser/parserapi.h"

extern const struct ParserRoutine *GetStandardParserRoutine(void);
extern void InitParserEngine(void);

#endif   /* PARSERENG_H */

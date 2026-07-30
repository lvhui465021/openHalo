/*-------------------------------------------------------------------------
 *
 * parsereng.h
 *    Parser engine selection and initialization.
 *
 * Portions Copyright (c) 2026, HaloLab / openHalo Contributors
 *
 * src/include/parser/parsereng.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PARSERENG_H
#define PARSERENG_H

#include "parser/parserapi.h"

typedef enum
{
	POSTGRESQL_COMPAT_MODE,
	MYSQL_COMPAT_MODE,
} DatabaseCompatModeType;

extern const struct ParserRoutine *GetStandardParserRoutine(void);
extern const struct ParserRoutine *GetMySQLParserRoutine(void);
extern void InitParserEngine(void);

/* Compile-time symbol for ProtocolRoutine initializer. */
extern const struct ParserRoutine MySQLParserRoutine;

/* GUC variable */
extern int database_compat_mode;

/* Parser Engine Instance */
extern const struct ParserRoutine *parserengine;

#endif   /* PARSERENG_H */

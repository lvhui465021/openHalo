/*-------------------------------------------------------------------------
 *
 * systemVar.h
 *    Minimal stub for MySQL system variable support.
 *
 * This is a placeholder.  Full MySQL system variable handling will be
 * migrated from openHalo in a later phase.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/adapter/mysql/systemVar.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef ADAPTER_MYSQL_SYSTEMVAR_H
#define ADAPTER_MYSQL_SYSTEMVAR_H

/* Stub: always returns false until full migration */
static inline bool
isSystemVariable(char *varName)
{
    return false;
}

#endif /* ADAPTER_MYSQL_SYSTEMVAR_H */

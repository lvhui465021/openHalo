/*-------------------------------------------------------------------------
 *
 * mys_compat.h
 *    Compatibility declarations for symbols that the UDB-TX analyze code
 *    expects from openHalo headers that are not (yet) present in PG18.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/mysql/mys_compat.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef MYS_COMPAT_H
#define MYS_COMPAT_H

/* GUC: enable MySQL-style multi-table UPDATE.  Set false for M3 baseline. */
extern bool unvdb_mysql_support_multiple_table_update;

#endif /* MYS_COMPAT_H */

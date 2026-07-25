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

#include "nodes/pg_list.h"

/* GUC: enable MySQL-style multi-table UPDATE.  Set false for M3 baseline. */
extern bool unvdb_mysql_support_multiple_table_update;

/* M3 stubs for UDB-TX MySQL DDL utility functions (see mys_utilcmd_stubs.c) */
extern Oid	getColumnDefaultSeq(Relation rel, const char *colName);
extern char *mysBuildSeqName(char *tableName);
extern char *mysBuildTrigFuncNameForAutoInc(char *tableName);
extern char *mysBuildTrigNameForAutoInc(char *tableName);
extern char *mysBuildTrigFuncNameForOnUpdateNow(char *tableName, char *colName);
extern char *mysBuildTrigNameForOnUpdateNow(char *tableName, char *colName);
extern Oid	mysGetColumnOnUpdateNowTrig(Relation rel, char *colName);
extern void mysProcessAutoIncForRenameAtt(Relation targetRel, char *oldColName,
                                          char *newColName, List **stmts);
extern char *mysBuildCheckNameForSet(void);
extern void mysProcessSetEnumForRenameAtt(Relation targetRel, char *oldColName,
                                          char *newColName, List **stmts);

#endif /* MYS_COMPAT_H */

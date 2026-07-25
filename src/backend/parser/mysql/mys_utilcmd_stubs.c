/*-------------------------------------------------------------------------
 *
 * mys_utilcmd_stubs.c
 *    Stub implementations for UDB-TX MySQL DDL utility functions not
 *    yet migrated to PG18.
 *
 * These will be properly migrated from openHalo's commands/mysql/ modules
 * in a later phase.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/parser/mysql/mys_utilcmd_stubs.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/relscan.h"
#include "catalog/namespace.h"
#include "nodes/nodes.h"
#include "utils/rel.h"

/*
 * getColumnDefaultSeq -- check if a column has an auto_increment default
 * sequence.
 *
 * M3 stub: returns InvalidOid (no sequence found).
 * The PG18 equivalent would require checking pg_attrdef and pg_depend.
 */
Oid
getColumnDefaultSeq(Relation rel, const char *colName)
{
    return InvalidOid;
}

/*
 * mysBuildSeqName -- build the sequence name for an auto_increment column.
 *
 * M3 stub: returns a default name.
 */
char *
mysBuildSeqName(char *tableName)
{
    return pstrdup(tableName); /* placeholder */
}

/*
 * mysBuildTrigFuncNameForAutoInc -- build the trigger function name for
 * auto_increment support.
 *
 * M3 stub: returns empty string.
 */
char *
mysBuildTrigFuncNameForAutoInc(char *tableName)
{
    return pstrdup(""); /* placeholder */
}

/*
 * mysBuildTrigNameForAutoInc -- build the trigger name for auto_increment.
 *
 * M3 stub: returns empty string.
 */
char *
mysBuildTrigNameForAutoInc(char *tableName)
{
    return pstrdup(""); /* placeholder */
}

/*
 * mysBuildTrigFuncNameForOnUpdateNow -- build the trigger function name
 * for ON UPDATE NOW() support.
 *
 * M3 stub: returns empty string.
 */
char *
mysBuildTrigFuncNameForOnUpdateNow(char *tableName, char *colName)
{
    return pstrdup(""); /* placeholder */
}

/*
 * mysBuildTrigNameForOnUpdateNow -- build the trigger name for ON UPDATE NOW().
 *
 * M3 stub: returns empty string.
 */
char *
mysBuildTrigNameForOnUpdateNow(char *tableName, char *colName)
{
    return pstrdup(""); /* placeholder */
}

/*
 * mysGetColumnOnUpdateNowTrig -- check if a column has an ON UPDATE NOW()
 * trigger and return its OID.
 *
 * M3 stub: returns InvalidOid.
 */
Oid
mysGetColumnOnUpdateNowTrig(Relation rel, char *colName)
{
    return InvalidOid;
}

/*
 * mysProcessAutoIncForRenameAtt -- process auto_increment column renames.
 *
 * M3 stub: no-op.
 */
void
mysProcessAutoIncForRenameAtt(Relation targetRel, char *oldColName,
                              char *newColName, List **stmts)
{
    /* no-op stub */
}

/*
 * mysBuildCheckNameForSet -- build the check constraint name for SET types.
 *
 * M3 stub: returns empty string.
 */
char *
mysBuildCheckNameForSet(void)
{
    return pstrdup(""); /* placeholder */
}

/*
 * mysProcessSetEnumForRenameAtt -- process SET/ENUM column renames.
 *
 * M3 stub: no-op.
 */
void
mysProcessSetEnumForRenameAtt(Relation targetRel, char *oldColName,
                              char *newColName, List **stmts)
{
    /* no-op stub */
}

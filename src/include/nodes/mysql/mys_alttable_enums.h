/*-------------------------------------------------------------------------
 *
 * mys_alttable_enums.h
 *    MySQL-specific AlterTableType and ConstraintType enum extensions.
 *
 * PG18's AlterTableType enum includes the MySQL-specific values used by this
 * parser.  Keep this header for MySQL DDL declarations, but do not remap
 * those values: collapsing MODIFY/CHANGE into AT_AddColumn loses the
 * operation's lifecycle semantics before utility execution.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/nodes/mysql/mys_alttable_enums.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef MYS_ALTTABLE_ENUMS_H
#define MYS_ALTTABLE_ENUMS_H

#include "nodes/parsenodes.h"

/*
 * CONSTR_AUTOINC and CONSTR_KEY are native ConstrType values in PG18's
 * parsenodes.h.  Do not alias them to CONSTR_DEFAULT: doing so erases the
 * MySQL grammar's AUTO_INCREMENT marker before utility transformation.
 */

/*
 * M3 WARNING: ONCONFLICT_REPLACE is currently mapped to ONCONFLICT_UPDATE
 * as a preprocessor define.  This is a temporary placeholder — the REPLACE
 * semantics (DELETE conflicting row + INSERT new row) differ from standard
 * ON CONFLICT DO UPDATE, and the code in mys_nodeModifyTable.c detects the
 * MySQL REPLACE intent through a separate path, not through this define.
 *
 * DO NOT use this define in new code.  Use explicit runtime checks instead.
 * See mys_nodeModifyTable.c:897-919 for the actual REPLACE implementation.
 */
#define ONCONFLICT_REPLACE  ONCONFLICT_UPDATE  /* M3 placeholder */

/* MySQL ignore statement flag */
extern bool isIgnoreStmt;

#endif /* MYS_ALTTABLE_ENUMS_H */

/*-------------------------------------------------------------------------
 *
 * mys_alttable_enums.h
 *    MySQL-specific AlterTableType and ConstraintType enum extensions.
 *
 * These extend PG18's standard enums with MySQL-specific values.
 * Defined as preprocessor constants to avoid modifying PG's enum definitions.
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

/* MySQL DDL extensions to AlterTableType */
#define AT_TableOption      AT_SetRelOptions   /* temporary mapping */
#define AT_ModifyColumn     AT_AddColumn       /* temporary mapping */
#define AT_ChangeColumn     AT_AddColumn       /* temporary mapping */
#define AT_DropPrimaryKey   AT_DropConstraint  /* temporary mapping */
#define AT_DropIndex        AT_DropInherit     /* temporary mapping */
#define AT_DropForeignKey   AT_DropConstraint  /* temporary mapping */
#define AT_DropCheck        AT_DropConstraint  /* temporary mapping */

/* MySQL constraint type extensions */
#define CONSTR_AUTOINC      CONSTR_DEFAULT     /* temporary mapping */
#define CONSTR_KEY          CONSTR_DEFAULT     /* temporary mapping */

/* MySQL ON CONFLICT extension */
#define ONCONFLICT_REPLACE  ONCONFLICT_UPDATE  /* temporary mapping */

/* MySQL ignore statement flag */
extern bool isIgnoreStmt;

#endif /* MYS_ALTTABLE_ENUMS_H */

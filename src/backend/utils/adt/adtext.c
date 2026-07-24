/*-------------------------------------------------------------------------
 *
 * adtext.c
 *    Extension dispatch for ADT Data Types.
 *
 * Selects the appropriate ADT Extension method table (standard PostgreSQL
 * or MySQL) based on the active protocol and database mode.  Called once
 * during backend startup.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/utils/adt/adtext.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "utils/adtext.h"
#include "utils/mysql/mys_adtext.h"

#include "miscadmin.h"
#include "libpq/libpq-be.h"


void InitADTExt(void);
const ADTExtMethod *adtext = NULL;

static const ADTExtMethod standard_adtext;


/*
 * Standard ADT Extension: all hooks are NULL (pass-through to built-in
 * PostgreSQL implementations).
 */
static const ADTExtMethod standard_adtext = {
	.pre_numeric_in = NULL,
	.post_numeric_out = NULL,
	.pre_time_in = NULL,
	.post_time_out = NULL,
	.pre_timetz_in = NULL,
	.post_timetz_out = NULL,
	.pre_timestamp_in = NULL,
	.post_timestamp_out = NULL,
	.date_in = NULL,
	.timestamp_in = NULL,
	.allow_zero_length_char_typmod = false
};

const ADTExtMethod *
GetStandardADTExt(void)
{
	return &standard_adtext;
}


/*
 * InitADTExt
 *
 * Selects the ADT extension table.  When a MySQL protocol is active,
 * the MySQL-specific ADT functions (mys_date_in, mys_timestamp_in, etc.)
 * are installed; otherwise the standard pass-through table is used.
 *
 * TODO: The MySQL protocol selection guard will be activated once
 *       the protocol-routine / database-mode infrastructure lands
 *       (e.g. unvdb_database_mode == MYSQL_COMPAT_MODE &&
 *        nodeTag(MyProcPort->protocol_handler) == T_MySQLProtocol).
 *       For now the code defaults to StandardADTExt, which is safe
 *       (no MySQL behaviour leaks through unless explicitly enabled).
 */
void
InitADTExt(void)
{
	/*
	 * When the protocol-mode infrastructure is ready, uncomment the
	 * selection logic below.
	 *
	 * For now always use the standard ADT extension.  The MySQL ADT
	 * files compile and are available, but won't be invoked until
	 * the mode switch is activated.
	 */

#if defined(MYSQL_PROTOCOL_ENABLED)
	if (MyProcPort != NULL &&
		unvdb_database_mode == MYSQL_COMPAT_MODE &&
		nodeTag(MyProcPort->protocol_handler) == T_MySQLProtocol)
	{
		adtext = GetMysADTExt();
	}
	else
#endif
	{
		adtext = GetStandardADTExt();
	}
}

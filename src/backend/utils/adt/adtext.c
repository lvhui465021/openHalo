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

#include "parser/parsereng.h"
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
 * Selects the ADT extension table based on database_compat_mode.
 * When running in MYSQL_COMPAT_MODE with an active MySQL protocol,
 * the MySQL-specific ADT functions (mys_date_in, mys_timestamp_in, etc.)
 * are installed; otherwise the standard pass-through table is used.
 */
void
InitADTExt(void)
{
	switch (database_compat_mode)
	{
		case POSTGRESQL_COMPAT_MODE:
			adtext = GetStandardADTExt();
			break;

		case MYSQL_COMPAT_MODE:

			if ((MyProcPort != NULL) &&
				(MyProcPort->protocol_kind == COMPAT_PROTOCOL_MYSQL))
			{
				adtext = GetMysADTExt();
			}
			else
			{
				adtext = GetStandardADTExt();
			}

			break;

		default:
			adtext = GetStandardADTExt();
			break;
	}
}

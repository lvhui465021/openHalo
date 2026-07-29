/*-------------------------------------------------------------------------
 * mysm_minimal.c
 *    Minimal MySQL supplementary functions for PG18.
 *
 * Contains only C functions that cannot be implemented as PL/pgSQL wrappers.
 * The full openHalo mysm library (13 files, ~10K lines) depends heavily on
 * PG14 internals; those functions will be re-implemented cleanly as needed.
 *------------------------------------------------------------------------- */
#include "postgres.h"
#include <math.h>
#include "fmgr.h"
#include "miscadmin.h"
#include "storage/lmgr.h"
#include "storage/lock.h"
#include "utils/builtins.h"
#include "utils/timestamp.h"
#include "adapter/mysql/mysql_packet.h"

PG_MODULE_MAGIC;

/* ----------------------------------------------------------------
 * get_lock / release_lock — MySQL advisory lock wrappers
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(mysm_get_lock);
Datum
mysm_get_lock(PG_FUNCTION_ARGS)
{
    text *lock_name = PG_GETARG_TEXT_PP(0);
    int   timeout   = PG_GETARG_INT32(1);
    /* Use PG advisory lock: return 1 on success, 0 on timeout, NULL on error */
    /* For now, always succeed */
    PG_RETURN_INT32(1);
}

PG_FUNCTION_INFO_V1(mysm_release_lock);
Datum
mysm_release_lock(PG_FUNCTION_ARGS)
{
    text *lock_name = PG_GETARG_TEXT_PP(0);
    PG_RETURN_INT32(1);
}

PG_FUNCTION_INFO_V1(mysm_is_used_lock);
Datum
mysm_is_used_lock(PG_FUNCTION_ARGS)
{
    PG_RETURN_NULL();
}

/* ----------------------------------------------------------------
 * getCurrentUser / getSessionUser
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(getCurrentUser);
Datum
getCurrentUser(PG_FUNCTION_ARGS)
{
    PG_RETURN_TEXT_P(cstring_to_text(GetUserNameFromId(GetUserId(), false)));
}

PG_FUNCTION_INFO_V1(getSessionUser);
Datum
getSessionUser(PG_FUNCTION_ARGS)
{
    PG_RETURN_TEXT_P(cstring_to_text(GetUserNameFromId(GetSessionUserId(), false)));
}

/* ----------------------------------------------------------------
 * ceil_for_mysql / floor_for_mysql — MySQL math semantics
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(ceil_for_mysql);
Datum
ceil_for_mysql(PG_FUNCTION_ARGS)
{
    float8 val = PG_GETARG_FLOAT8(0);
    PG_RETURN_FLOAT8(ceil(val));
}

PG_FUNCTION_INFO_V1(floor_for_mysql);
Datum
floor_for_mysql(PG_FUNCTION_ARGS)
{
    float8 val = PG_GETARG_FLOAT8(0);
    PG_RETURN_FLOAT8(floor(val));
}

/* ----------------------------------------------------------------
 * timestampdiff — MySQL TIMESTAMPDIFF
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(timestampdiff);
Datum
timestampdiff(PG_FUNCTION_ARGS)
{
    text *unit_text = PG_GETARG_TEXT_PP(0);
    Timestamp dt1 = PG_GETARG_TIMESTAMP(1);
    Timestamp dt2 = PG_GETARG_TIMESTAMP(2);
    char *unit = text_to_cstring(unit_text);
    int64 diff;

    if (TIMESTAMP_NOT_FINITE(dt1) || TIMESTAMP_NOT_FINITE(dt2))
        PG_RETURN_NULL();

    diff = dt2 - dt1;  /* microseconds */

    if (pg_strcasecmp(unit, "second") == 0 || pg_strcasecmp(unit, "SECOND") == 0)
        PG_RETURN_INT64(diff / USECS_PER_SEC);
    else if (pg_strcasecmp(unit, "minute") == 0 || pg_strcasecmp(unit, "MINUTE") == 0)
        PG_RETURN_INT64(diff / USECS_PER_MINUTE);
    else if (pg_strcasecmp(unit, "hour") == 0 || pg_strcasecmp(unit, "HOUR") == 0)
        PG_RETURN_INT64(diff / USECS_PER_HOUR);
    else if (pg_strcasecmp(unit, "day") == 0 || pg_strcasecmp(unit, "DAY") == 0)
        PG_RETURN_INT64(diff / USECS_PER_DAY);
    else if (pg_strcasecmp(unit, "week") == 0 || pg_strcasecmp(unit, "WEEK") == 0)
        PG_RETURN_INT64(diff / (USECS_PER_DAY * 7));
    else if (pg_strcasecmp(unit, "month") == 0 || pg_strcasecmp(unit, "MONTH") == 0)
        PG_RETURN_INT64(diff / (USECS_PER_DAY * 30)); /* approximate */
    else if (pg_strcasecmp(unit, "quarter") == 0 || pg_strcasecmp(unit, "QUARTER") == 0)
        PG_RETURN_INT64(diff / (USECS_PER_DAY * 90)); /* approximate */
    else if (pg_strcasecmp(unit, "year") == 0 || pg_strcasecmp(unit, "YEAR") == 0)
        PG_RETURN_INT64(diff / (USECS_PER_DAY * 365)); /* approximate */
    else
        PG_RETURN_INT64(diff / USECS_PER_DAY); /* default: days */
}

/* ----------------------------------------------------------------
 * substringIndex — MySQL SUBSTRING_INDEX
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(substringIndex);
Datum
substringIndex(PG_FUNCTION_ARGS)
{
    text *str = PG_GETARG_TEXT_PP(0);
    text *delim = PG_GETARG_TEXT_PP(1);
    int32 count = PG_GETARG_INT32(2);
    char *s = text_to_cstring(str);
    char *d = text_to_cstring(delim);
    int dlen = strlen(d);
    char *result;

    if (count == 0)
        PG_RETURN_TEXT_P(cstring_to_text(""));

    if (count > 0) {
        int found = 0;
        char *p = s;
        char *last = s;
        while (*p && found < count) {
            if (strncmp(p, d, dlen) == 0) {
                found++;
                if (found == count) {
                    result = pnstrdup(s, p - s);
                    PG_RETURN_TEXT_P(cstring_to_text(result));
                }
                p += dlen;
            } else {
                p++;
            }
        }
        PG_RETURN_TEXT_P(cstring_to_text(s));
    } else {
        int found = 0;
        char *p = s + strlen(s) - 1;
        while (p >= s) {
            if (p >= s + dlen - 1 && strncmp(p - dlen + 1, d, dlen) == 0) {
                found--;
                if (found == count) {
                    result = pstrdup(p + 1);
                    PG_RETURN_TEXT_P(cstring_to_text(result));
                }
                p -= dlen;
            } else {
                p--;
            }
        }
        PG_RETURN_TEXT_P(cstring_to_text(s));
    }
}

/* ----------------------------------------------------------------
 * convertTextToDouble, convertTextToInt8 — type conversion helpers
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(convertTextToDouble);
Datum
convertTextToDouble(PG_FUNCTION_ARGS)
{
    text *t = PG_GETARG_TEXT_PP(0);
    char *s = text_to_cstring(t);
    PG_RETURN_FLOAT8(strtod(s, NULL));
}

PG_FUNCTION_INFO_V1(convertTextToInt8);
Datum
convertTextToInt8(PG_FUNCTION_ARGS)
{
    text *t = PG_GETARG_TEXT_PP(0);
    char *s = text_to_cstring(t);
    PG_RETURN_INT64(strtoll(s, NULL, 10));
}

/* ----------------------------------------------------------------
 * rowCount, mysFoundRows, mysLastInsertId — session state accessors
 * ---------------------------------------------------------------- */
PG_FUNCTION_INFO_V1(rowCount);
Datum
rowCount(PG_FUNCTION_ARGS)
{
    PG_RETURN_INT64(0); /* handled by capture_session_state + extension SQL */
}

PG_FUNCTION_INFO_V1(mysFoundRows);
Datum
mysFoundRows(PG_FUNCTION_ARGS)
{
    PG_RETURN_INT64(0);
}

PG_FUNCTION_INFO_V1(mysLastInsertId);
Datum
mysLastInsertId(PG_FUNCTION_ARGS)
{
    PG_RETURN_INT64(0);
}

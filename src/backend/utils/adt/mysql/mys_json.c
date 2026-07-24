/*-------------------------------------------------------------------------
 *
 * mys_json.c
 *    MySQL ADT compatibility: JSON function wrappers.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/utils/adt/mysql/mys_json.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

 #include "utils/fmgrprotos.h"
 #include "utils/mysql/mys_json.h"
 
 Datum
 mys_json_object(PG_FUNCTION_ARGS)
 {
     return json_build_object(fcinfo);
 }
 
 Datum
 mys_json_object_noargs(PG_FUNCTION_ARGS)
 {
     return json_build_object_noargs(fcinfo);
 }
 
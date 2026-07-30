/*-------------------------------------------------------------------------
 *
 * mys_json.c
 *    MySQL ADT compatibility: JSON function wrappers.
 *
 * Portions Copyright (c) 2026, HaloLab / openHalo Contributors
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

/*
 * PG16 exposed json(int2/int4/int8/float4/float8/numeric) through six
 * type-specific wrappers.  PG18 removed those C entry points, but keeps the
 * generic to_json(anyelement) implementation.  The catalog compatibility
 * overloads retain the old SQL surface and delegate serialization to that
 * native PG18 path.
 */
Datum
mys_to_json(PG_FUNCTION_ARGS)
{
	return to_json(fcinfo);
}

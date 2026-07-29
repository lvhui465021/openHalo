/*-------------------------------------------------------------------------
 *
 * aggregates.c
 *	  Extend aggregate routines
 *
 * 

 * 
 *
 * IDENTIFICATION
 *	  src/backend/utils/ddsm/mysm/aggregates.c
 *
 *-------------------------------------------------------------------------
 */

#include "unvdb.h"

#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/fmgrprotos.h"


PG_FUNCTION_INFO_V1(textAvgAccum);
/*
 * Generic transition function for numeric aggregates that don't require sumX2.
 */
Datum
textAvgAccum(PG_FUNCTION_ARGS)
{
    Datum orgDatum1 = PG_GETARG_DATUM(1);
    Datum result;

    if (!PG_ARGISNULL(1))
    {
        char *num = TextDatumGetCString(orgDatum1);

        fcinfo->args[1].value = DirectFunctionCall3(numeric_in,
                                CStringGetDatum(num),
                                ObjectIdGetDatum(InvalidOid),
                                Int32GetDatum(-1));
    }

	result = numeric_avg_accum(fcinfo);

    fcinfo->args[1].value = orgDatum1;

    return result;
}






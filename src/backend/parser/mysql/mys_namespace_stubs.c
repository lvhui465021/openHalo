/*-------------------------------------------------------------------------
 *
 * mys_namespace_stubs.c
 *    Stub implementations for MySQL parser namespace functions.
 *
 * These will be properly migrated from openHalo's catalog/namespace.c
 * and commands/mysql/ modules in a later phase.
 *
 * Portions Copyright (c) 2026, HaloLab / openHalo Contributors
 *
 * src/backend/parser/mysql/mys_namespace_stubs.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "catalog/namespace.h"
#include "utils/guc.h"

/*
 * getCurrentNamespaceOid -- return the OID of the "current" namespace.
 *
 * M2 stub: returns the first namespace on the active search path.
 * This will be replaced with proper MySQL schema handling when the
 * MySQL namespace module is migrated from openHalo.
 */
Oid
getCurrentNamespaceOid(void)
{
    List       *search_path;

    search_path = fetch_search_path(false);
    if (search_path != NIL)
        return linitial_oid(search_path);

    return InvalidOid;
}

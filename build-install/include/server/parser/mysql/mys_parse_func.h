/*-------------------------------------------------------------------------
 *
 * mys_parse_func.h
 *    MySQL parser support declarations.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/parser/mysql/mys_parse_func.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef MYS_PARSE_FUNC_H
#define MYS_PARSE_FUNC_H

#include "postgres.h"

#include "parser/parse_func.h"
#include "parser/parse_node.h"

Node *mys_ParseFuncOrColumn(ParseState *pstate, List *funcname, List *fargs,
	    			      Node *last_srf, FuncCall *fn, bool proc_call, int location);
void mys_make_fn_arguments(ParseState *pstate,
                           List *fargs,
                           Oid *actual_arg_types,
                           Oid *declared_arg_types);
FuncDetailCode mys_func_get_detail(List *funcname, List *fargs,
                                   List *fargnames, int nargs,
                                   Oid *argtypes, bool expand_variadic,
                                   bool expand_defaults, bool include_out_arguments,
                                   Oid *funcid, Oid *rettype,
                                   bool *retset, int *nvargs,
                                   Oid *vatype, Oid **true_typeids,
                                   List **argdefaults);

#endif							/* MYS_PARSE_FUNC_H */


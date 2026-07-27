#include "postgres.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "nodes/pg_list.h"
#include "nodes/value.h"
#include "nodes/mysql/mys_parsenodes.h"
#include "parser/parserapi.h"
#include "parser/parse_expr.h"
#include "parser/parse_node.h"
#include "parser/mysql/mys_expr_transform.h"

static Node *
mys_transform_user_var_call(ParseState *pstate, const char *function_name,
							const char *user_var_name, Node *value,
							ParseLoc location)
{
	A_Const    *name;
	List       *args;
	FuncCall   *call;

	name = makeNode(A_Const);
	name->val.sval.type = T_String;
	name->val.sval.sval = pstrdup(user_var_name);
	name->location = location;

	args = list_make1(name);
	if (value != NULL)
		args = lappend(args, value);

	call = makeFuncCall(list_make2(makeString("pg_catalog"),
								 makeString(pstrdup(function_name))),
					args, COERCE_EXPLICIT_CALL, location);

	return transformExpr(pstate, (Node *) call, pstate->p_expr_kind);
}

static Node *
mys_transform_noarg_call(ParseState *pstate, const char *function_name,
					 ParseLoc location)
{
	FuncCall   *call;

	call = makeFuncCall(list_make2(makeString("pg_catalog"),
								 makeString(pstrdup(function_name))),
					NIL, COERCE_EXPLICIT_CALL, location);
	return transformExpr(pstate, (Node *) call, pstate->p_expr_kind);
}

/*
 * MySQL exposes the source spelling of unaliased literals as their result
 * column label (for example, SELECT 1 produces a column named "1").  The
 * PostgreSQL default is "?column?".  This hook only handles expressions for
 * which MySQL has a dialect-specific label and lets FigureColname() handle
 * every other raw node.
 */
char *
mys_figure_colname(Node *expr)
{
	A_Const    *constant;

	if (expr == NULL)
		return NULL;

	if (IsA(expr, A_Const))
	{
		constant = (A_Const *) expr;
		if (constant->isnull)
			return pstrdup("NULL");

		switch (constant->val.node.type)
		{
			case T_Integer:
				return psprintf("%d", constant->val.ival.ival);
			case T_Float:
				return pstrdup(constant->val.fval.fval);
			case T_String:
				return pstrdup(constant->val.sval.sval);
			case T_Boolean:
				return pstrdup(constant->val.boolval.boolval ? "TRUE" : "FALSE");
			case T_BitString:
				return pstrdup(constant->val.bsval.bsval);
			default:
				return NULL;
		}
	}

	if (IsA(expr, UserVarRef))
		return psprintf("@%s", ((UserVarRef *) expr)->userVarName);

	return NULL;
}

/*
 * Lower MySQL-specific raw expression nodes to standard PG nodes.
 *
 * System variables with real session semantics are lowered to volatile
 * builtins here.  Read-only compatibility probes retain their historic
 * literal results.  UserVarRef and UserVarAssign are lowered here too.
 */
bool
mys_transform_expr_node(ParseState *pstate, Node *expr, Node **result)
{
    if (expr == NULL)
        return false;

    switch (nodeTag(expr))
    {
    case T_SysVarRef:
        {
            SysVarRef  *sv = (SysVarRef *) expr;
            const char *val;

            if (pg_strcasecmp(sv->sysVarName, "time_zone") == 0 ||
                pg_strcasecmp(sv->sysVarName, "session.time_zone") == 0 ||
                pg_strcasecmp(sv->sysVarName, "local.time_zone") == 0)
            {
                *result = mys_transform_noarg_call(pstate,
                                                    "mys_get_session_time_zone",
                                                    sv->location);
                return true;
            }
			else if (pg_strcasecmp(sv->sysVarName, "global.time_zone") == 0)
			{
				*result = mys_transform_noarg_call(pstate,
													"mys_get_global_time_zone",
													sv->location);
				return true;
			}
            else if (pg_strcasecmp(sv->sysVarName, "version_comment") == 0)
                val = "8.0.40-openhalo-1.0";
            else if (pg_strcasecmp(sv->sysVarName, "version") == 0)
                val = "8.0.40";
            else
                val = sv->sysVarName;

            *result = (Node *) make_const(pstate,
                         (A_Const *) makeStringConst(pstrdup(val), sv->location));
            return true;
        }

	case T_UserVarRef:
		{
			UserVarRef *uv = (UserVarRef *) expr;

			*result = mys_transform_user_var_call(pstate,
											"mys_get_user_var", uv->userVarName,
											NULL, uv->location);
			return true;
		}

    case T_UserVarAssign:
        {
            UserVarAssign *ua = (UserVarAssign *) expr;
			*result = mys_transform_user_var_call(pstate,
											"mys_set_user_var", ua->userVarName,
											ua->expr, ua->location);
            return true;
        }

    default:
        break;
    }

    return false;
}

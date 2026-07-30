#include "postgres.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "nodes/pg_list.h"
#include "nodes/value.h"
#include "nodes/mysql/mys_parsenodes.h"
#include "commands/mysql/mys_uservar.h"
#include "parser/parserapi.h"
#include "parser/parse_coerce.h"
#include "parser/parse_expr.h"
#include "parser/parse_node.h"
#include "parser/mysql/mys_expr_transform.h"
#include "adapter/mysql/systemVar.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"

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
	{
		if (IsA(value, A_Const) &&
			(castNode(A_Const, value)->isnull ||
			 castNode(A_Const, value)->val.node.type == T_String))
		{
			TypeCast *cast = makeNode(TypeCast);

			cast->arg = value;
			cast->typeName = makeTypeName(pstrdup("text"));
			cast->location = location;
			value = (Node *) cast;
		}
		args = lappend(args, value);
	}

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

static Node *
mys_transform_system_var_call(ParseState *pstate, const char *name,
						  bool is_session, ParseLoc location)
{
	FuncCall   *call;
	List	   *args;

	args = list_make2(makeStringConst(pstrdup(name), location),
					  makeStringConst(is_session ? "true" : "false", location));
	call = makeFuncCall(list_make2(makeString("pg_catalog"),
								 makeString("mys_get_system_variable")),
					args, COERCE_EXPLICIT_CALL, location);
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
			const char *sql_mode_name = NULL;
			bool		is_session = true;

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
			else if (pg_strcasecmp(sv->sysVarName, "autocommit") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "session.autocommit") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "local.autocommit") == 0)
				val = MysAutocommitEnabled() ? "1" : "0";
			else if (pg_strcasecmp(sv->sysVarName, "character_set_client") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "character_set_connection") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "character_set_results") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "character_set_server") == 0)
				val = "utf8mb4";
			else if (pg_strcasecmp(sv->sysVarName, "collation_connection") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "session.collation_connection") == 0)
				val = "utf8mb4_general_ci";
			else if (pg_strcasecmp(sv->sysVarName, "collation_server") == 0)
				val = "utf8mb4_general_ci";
			else if (pg_strcasecmp(sv->sysVarName, "collation_database") == 0)
				val = "utf8mb4_general_ci";
			else if (pg_strcasecmp(sv->sysVarName, "max_allowed_packet") == 0)
				val = "16777216";
			else if (pg_strcasecmp(sv->sysVarName, "sql_mode") == 0)
				sql_mode_name = "sql_mode";
			else if (pg_strcasecmp(sv->sysVarName, "session.sql_mode") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "local.sql_mode") == 0)
				sql_mode_name = "sql_mode";
			else if (pg_strcasecmp(sv->sysVarName, "global.sql_mode") == 0)
			{
				sql_mode_name = "sql_mode";
				is_session = false;
			}
			else if (pg_strcasecmp(sv->sysVarName, "wait_timeout") == 0 ||
					 pg_strcasecmp(sv->sysVarName, "interactive_timeout") == 0)
				val = "28800";
            else if (pg_strcasecmp(sv->sysVarName, "version_comment") == 0)
                val = mysql_server_version;
            else if (pg_strcasecmp(sv->sysVarName, "version") == 0)
                val = mysql_server_version;
			else
				val = sv->sysVarName;

			if (sql_mode_name != NULL)
			{
				*result = mys_transform_system_var_call(pstate, sql_mode_name,
												 is_session, sv->location);
				return true;
			}

            *result = (Node *) make_const(pstate,
                         (A_Const *) makeStringConst(pstrdup(val), sv->location));
            return true;
        }

	case T_UserVarRef:
		{
			UserVarRef *uv = (UserVarRef *) expr;
			Oid		valueType;

			*result = mys_transform_user_var_call(pstate,
											"mys_get_user_var", uv->userVarName,
											NULL, uv->location);
			valueType = mysGetUserVarTypeInternal(uv->userVarName);
			if (OidIsValid(valueType))
			{
				Node *coerced = coerce_to_target_type(pstate, *result,
															TEXTOID, getBaseType(valueType), -1,
															COERCION_EXPLICIT,
															COERCE_EXPLICIT_CAST,
															uv->location);

				if (coerced == NULL)
					ereport(ERROR,
							(errcode(ERRCODE_CANNOT_COERCE),
							 errmsg("cannot coerce MySQL user variable")));
				*result = coerced;
			}
			return true;
		}

	case T_A_Expr:
		{
			A_Expr *aexpr = (A_Expr *) expr;
			const char *opname = NULL;

			/* MySQL <=> is SQL's null-safe equality operator. */
			if (aexpr->kind == AEXPR_OP && list_length(aexpr->name) == 1 &&
				strcmp(strVal(linitial(aexpr->name)), "<=>") == 0)
			{
				aexpr->kind = AEXPR_NOT_DISTINCT;
				aexpr->name = list_make1(makeString("="));
				*result = transformExpr(pstate, (Node *) aexpr,
										pstate->p_expr_kind);
				return true;
			}

			if (aexpr->kind == AEXPR_OP && list_length(aexpr->name) == 1)
				opname = strVal(linitial(aexpr->name));

			/*
			 * In non-strict mode MySQL converts an empty string to zero in a
			 * numeric expression.  Do this while the raw literal and session
			 * sql_mode are still visible; PG18's normal operator resolver can
			 * then select its native numeric operator without weakening any
			 * PostgreSQL input function or cast globally.
			 */
			if (opname != NULL &&
				(strcmp(opname, "+") == 0 || strcmp(opname, "-") == 0 ||
				 strcmp(opname, "*") == 0 || strcmp(opname, "/") == 0 ||
				 strcmp(opname, "%") == 0) &&
				(mys_sqlMode & (MYS_MODE_STRICT_TRANS_TABLES |
								MYS_MODE_STRICT_ALL_TABLES)) == 0)
			{
				Node **operands[2] = {&aexpr->lexpr, &aexpr->rexpr};
				int i;

				for (i = 0; i < lengthof(operands); i++)
				{
					Node *operand = *operands[i];

					if (operand != NULL && IsA(operand, A_Const))
					{
						A_Const *constant = (A_Const *) operand;

						if (!constant->isnull &&
							constant->val.node.type == T_String &&
							constant->val.sval.sval[0] == '\0')
						{
							constant->val.node.type = T_Integer;
							constant->val.ival.ival = 0;
						}
					}
				}
			}
			break;
		}

	case T_FuncCall:
		{
			FuncCall *fn = (FuncCall *) expr;
			bool		is_mysql_concat = false;

			/*
			 * PG16 routed function resolution through mys_ParseFuncOrColumn(),
			 * which renamed these MySQL spellings before catalog lookup.  PG18's
			 * ParserRoutine exposes the earlier expression hook instead, so do
			 * the same raw-name lowering here and let normal resolution continue.
			 */
			if (list_length(fn->funcname) == 1)
			{
				char *fname = strVal(linitial(fn->funcname));

				if (pg_strcasecmp(fname, "json_object") == 0)
					fn->funcname = list_make1(makeString("mys_json_object"));
				else if (pg_strcasecmp(fname, "json_array") == 0)
					fn->funcname = list_make1(makeString("json_build_array"));
			}

			if (fn->args != NIL && fn->agg_order == NIL &&
				fn->agg_filter == NULL && fn->over == NULL &&
				!fn->agg_star && !fn->agg_distinct)
			{
				if (list_length(fn->funcname) == 1)
					is_mysql_concat =
						pg_strcasecmp(strVal(linitial(fn->funcname)), "concat") == 0;
				else if (list_length(fn->funcname) == 2)
					is_mysql_concat =
						pg_strcasecmp(strVal(linitial(fn->funcname)), "mysql") == 0 &&
						pg_strcasecmp(strVal(lsecond(fn->funcname)), "concat") == 0;
			}

			/*
			 * MySQL CONCAT converts every argument to text before concatenating.
			 * A VARIADIC text[] extension function cannot request those explicit
			 * casts itself, so preserve the raw call and cast each argument here.
			 */
			if (is_mysql_concat)
			{
				List	   *args = NIL;
				ListCell   *lc;

				foreach(lc, fn->args)
				{
					TypeCast *cast = makeNode(TypeCast);

					cast->arg = lfirst(lc);
					cast->typeName = makeTypeName(pstrdup("text"));
					cast->location = fn->location;
					args = lappend(args, cast);
				}
				fn->args = args;
				return false;
			}

			/*
			 * Intercept VERSION() in MySQL protocol: return the MySQL
			 * server version from GUC instead of PG's built-in version().
			 * Match only the unqualified, no-argument form so that
			 * pg_catalog.version() still returns the PG version.
			 */
			if (fn->args == NIL && fn->agg_order == NIL &&
				fn->agg_filter == NULL && fn->over == NULL &&
				!fn->agg_star && !fn->agg_distinct &&
				list_length(fn->funcname) == 1)
			{
				char *fname = strVal(linitial(fn->funcname));

				if (pg_strcasecmp(fname, "version") == 0)
				{
					*result = (Node *) make_const(pstate,
						(A_Const *) makeStringConst(
							pstrdup(mysql_server_version),
							fn->location));
					return true;
				}
			}
			break;
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

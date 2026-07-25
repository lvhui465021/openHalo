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

/*
 * Lower MySQL-specific raw expression nodes to standard PG nodes.
 *
 * SysVarRef is now handled directly in the grammar (produces A_Const).
 * UserVarRef and UserVarAssign are lowered here.
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

            if (pg_strcasecmp(sv->sysVarName, "version_comment") == 0)
                val = "8.0.40-openhalo-1.0";
            else if (pg_strcasecmp(sv->sysVarName, "version") == 0)
                val = "8.0.40";
            else
                val = sv->sysVarName;

            *result = makeStringConst(pstrdup(val), sv->location);
            return true;
        }

    case T_UserVarRef:
        *result = (Node *) makeNullConst(UNKNOWNOID, -1, InvalidOid);
        return true;

    case T_UserVarAssign:
        {
            UserVarAssign *ua = (UserVarAssign *) expr;
            if (ua->expr != NULL)
            {
                *result = ua->expr;
                return true;
            }
            *result = (Node *) makeNullConst(UNKNOWNOID, -1, InvalidOid);
            return true;
        }

    default:
        break;
    }

    return false;
}

/*-------------------------------------------------------------------------
 *
 * mys_analyze.c
 *    MySQL-specific semantic analysis: transforms raw parse trees into Query nodes.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/backend/parser/mysql/mys_analyze.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "miscadmin.h"

#include "access/genam.h"
#include "access/relation.h"
#include "access/skey.h"
#include "catalog/dependency.h"
#include "catalog/namespace.h"
#include "catalog/pg_attrdef.h"
#include "catalog/pg_attribute.h"
#include "catalog/pg_depend.h"
#include "catalog/pg_proc.h"
#include "nodes/nodeFuncs.h"
#include "nodes/makefuncs.h"
#include "nodes/parsenodes.h"
#include "nodes/mysql/mys_parsenodes.h"
#include "parser/analyze.h"
#include "parser/parsetree.h"
#include "parser/parse_agg.h"
#include "parser/parse_clause.h"
#include "parser/parse_coerce.h"
#include "parser/parse_collate.h"
#include "parser/parse_cte.h"
#include "parser/parse_expr.h"
#include "parser/parse_relation.h"
#include "parser/parse_target.h"
#include "parser/parse_type.h"
#include "parser/parserapi.h"
#include "parser/mysql/mys_analyze.h"
#include "parser/mysql/mys_parse_agg.h"
#include "utils/builtins.h"
#include "utils/catcache.h"
#include "utils/fmgroids.h"
#include "utils/hsearch.h"
#include "utils/rel.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "optimizer/optimizer.h"
#include "parser/mysql/mys_compat.h"
#include "utils/array.h"

typedef struct 
{
    char alias[NAMEDATALEN];   /* hash key must be first item */
    Node *expr;
} AliasExpr;

/* M3: inlined */
/* M3: inlined */
/* M3: inlined */
static List *retrieveSetTargets(List *totalTargetList, RangeVar *relation);
static Node *mergeWhereClauseOnClause(Node *whereClause, Node *onClause);
static void rectifyExpr(RangeVar *relation, char *newVal, Node *expr);
static void rectifyColumnRef(RangeVar *relation, char *newVal, ColumnRef *columnRef);
/* M3: inlined */
static void determineRecursiveColTypes(ParseState *pstate, Node *larg, List *nrtargetlist);
static void rectifyHavingClause(SelectStmt *stmt);
static void rectifyHavingAlias(HTAB *aliases, Node *expr);


/*
 * mys_transformOptionalSelectInto -
 *	  If SELECT has INTO, convert it to MysSelectIntoStmt.
 *
 * The only thing we do here that we don't do in transformStmt() is to
 * convert SELECT ... INTO into MysSelectIntoStmt.  Since utility statements
 * aren't allowed within larger statements, this is only allowed at the top
 * of the parse tree, and so we only try it before entering the recursive
 * transformStmt() processing.
 */
Query *
mys_transformOptionalSelectInto(ParseState *pstate, Node *parseTree)
{
	return transformStmt(pstate, parseTree); /* M3: delegate to PG18 */
}


/*
 * mys_transformStmt -
 *	  recursively transform a Parse tree into a Query tree.
 */
Query *
mys_transformStmt(ParseState *pstate, Node *parseTree)
{
	return transformStmt(pstate, parseTree); /* M3: delegate to PG18 */
}


static Query *
transformMysVariableSetStmt(ParseState *pstate, MysVariableSetStmt *stmt)
{
	Query *result = makeNode(Query);
	result->commandType = CMD_UTILITY;
	result->utilityStmt = (Node *) stmt;
	result->querySource = QSRC_ORIGINAL;
	result->canSetTag = true;
	return result;
}


/*
 * For select into,
 * stored procedures have their own process, can't reach here
 */
static Query *
transformMysSelectIntoStmt(ParseState *pstate, MysSelectIntoStmt *stmt)
{
	Query *result = makeNode(Query);
	result->commandType = CMD_UTILITY;
	result->utilityStmt = (Node *) stmt;
	result->querySource = QSRC_ORIGINAL;
	result->canSetTag = true;
	return result;
}


static Query *
transformUpdateStmtInternal(ParseState *pstate, UpdateStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}


/*
 * mys_stmt_requires_parse_analysis
 *		Returns true if parse analysis will do anything non-trivial
 *		with the given raw parse tree.
 *
 * Generally, this should return true for any statement type for which
 * transformStmt() does more than wrap a CMD_UTILITY Query around it.
 * When it returns false, the caller can assume that there is no situation
 * in which parse analysis of the raw statement could need to be re-done.
 *
 * Currently, since the rewriter and planner do nothing for CMD_UTILITY
 * Queries, a false result means that the entire parse analysis/rewrite/plan
 * pipeline will never need to be re-done.  If that ever changes, callers
 * will likely need adjustment.
 */
bool
mys_stmt_requires_parse_analysis(RawStmt *parseTree)
{
	bool		result;

	switch (nodeTag(parseTree->stmt))
	{
			/*
			 * Optimizable statements
			 */
		case T_InsertStmt:
		case T_DeleteStmt:
		case T_UpdateStmt:
		case T_SelectStmt:
		case T_ReturnStmt:
		case T_PLAssignStmt:
			result = true;
			break;

			/*
			 * Special cases
			 */
		case T_DeclareCursorStmt:
		case T_ExplainStmt:
		case T_CreateTableAsStmt:
		case T_CallStmt:
        case T_MysVariableSetStmt:
			result = true;
			break;

		default:
			/* all other statements just get wrapped in a CMD_UTILITY Query */
			result = false;
			break;
	}

	return result;
}

/*
 * mys_analyze_requires_snapshot
 *		Returns true if a snapshot must be set before doing parse analysis
 *		on the given raw parse tree.
 */
bool
mys_analyze_requires_snapshot(RawStmt *parseTree)
{
	return mys_stmt_requires_parse_analysis(parseTree);
}

static void
mys_construct_returningList(ParseState *pstate, InsertStmt *stmt)
{
    Relation resultRelation;
    TupleDesc tupledesc;
    TupleConstr *constr;
    //Oid namespaceId;
    //char seqname[512];
    char *auto_increment_column;
    //int i = 0;

    Assert(stmt->returningList == NULL);

    resultRelation = pstate->p_target_relation;
    tupledesc = resultRelation->rd_att;
    constr = tupledesc->constr;
    //namespaceId = ((Form_pg_class)(resultRelation->rd_rel))->relnamespace;

    if ((constr == NULL) || (constr != NULL && constr->num_defval <= 0))
    {
        return;
    }
    else
    {
        Relation attrdef;
        Relation depRel;
        int i = 0;

        attrdef = relation_open(AttrDefaultRelationId, AccessShareLock);
        depRel = relation_open(DependRelationId, AccessShareLock);
        for (i = 0; i < constr->num_defval; i++)
        {
            bool isAutoIncrement = false;
            AttrDefault attrdefault = constr->defval[i];
            ScanKeyData keys[2];
            SysScanDesc scan;
            HeapTuple attrdefTuple;
            Oid columnDefaultOid;
            HeapTuple depTuple;

            ScanKeyInit(&keys[0],
                        Anum_pg_attrdef_adrelid,
                        BTEqualStrategyNumber,
                        F_OIDEQ,
                        ObjectIdGetDatum(RelationGetRelid(resultRelation)));
            ScanKeyInit(&keys[1],
                        Anum_pg_attrdef_adnum,
                        BTEqualStrategyNumber,
                        F_INT2EQ,
                        Int16GetDatum(attrdefault.adnum));
            scan = systable_beginscan(attrdef, AttrDefaultIndexId, true,
                                      NULL, 2, keys);
            attrdefTuple = systable_getnext(scan);
            columnDefaultOid = ((Form_pg_attrdef)GETSTRUCT(attrdefTuple))->oid;
            systable_endscan(scan);

            ScanKeyInit(&keys[0],
                        Anum_pg_depend_classid,
                        BTEqualStrategyNumber, F_OIDEQ,
                        ObjectIdGetDatum(AttrDefaultRelationId));
	        ScanKeyInit(&keys[1],
                        Anum_pg_depend_objid,
                        BTEqualStrategyNumber, F_OIDEQ,
                        ObjectIdGetDatum(columnDefaultOid));
            
            scan = systable_beginscan(depRel, DependDependerIndexId, true,
							          NULL, 2, keys);
            while (HeapTupleIsValid(depTuple = systable_getnext(scan)))
            {
                Form_pg_depend foundDep = (Form_pg_depend) GETSTRUCT(depTuple);

                if (foundDep->refclassid == RelationRelationId &&
                    foundDep->objsubid == 0 &&
                    foundDep->refobjsubid == 0 &&
                    foundDep->deptype == DEPENDENCY_NORMAL &&
                    get_rel_relkind(foundDep->refobjid) == RELKIND_SEQUENCE)
                {
                    isAutoIncrement = true;
                }
            }
            systable_endscan(scan);

            if (isAutoIncrement)
            {
                FormData_pg_attribute attr = tupledesc->attrs[attrdefault.adnum - 1];
                ResTarget *restarget = makeNode(ResTarget);
                ColumnRef *columnref = makeNode(ColumnRef);
                List *returning = list_make1(restarget);

                auto_increment_column = pstrdup(NameStr(attr.attname));

                columnref->fields = lcons(makeString(auto_increment_column), NULL);
                restarget->name = NULL;
                restarget->indirection = NIL;
                restarget->val = (Node *)columnref;

                stmt->returningList = returning;

                break;
            }
        }
        relation_close(attrdef, AccessShareLock);
        relation_close(depRel, AccessShareLock);
    }

    // for (i = 0; i < tupledesc->natts; i++)
    // {
    //     Oid seq_oid;
    //     FormData_pg_attribute attr = tupledesc->attrs[i];
    //     sprintf(seqname, "%s_%s_seq", NameStr(((Form_pg_class)(resultRelation->rd_rel))->relname), NameStr(attr.attname));

    //     seq_oid = GetSysCacheOid2(RELNAMENSP, Anum_pg_class_oid,
	// 							 PointerGetDatum(seqname),
	// 							 ObjectIdGetDatum(namespaceId));
        
    //     if (OidIsValid(seq_oid))
    //     {
    //         ResTarget *restarget = makeNode(ResTarget);
    //         ColumnRef *columnref = makeNode(ColumnRef);
    //         List *returning = list_make1(restarget);

    //         auto_increment_column = strdup(NameStr(attr.attname));

    //         columnref->fields = lcons(makeString(auto_increment_column), NULL);
    //         restarget->name = NULL;
    //         restarget->indirection = NIL;
    //         restarget->val = (Node *)columnref;

    //         stmt->returningList = returning;
    //         break;
    //     }
    // }
}

/*
 * mys_transformSelectStmt -
 *	  transforms a Select Statement
 *
 * Note: this covers only cases with no set operations and no VALUES lists;
 * see below for the other cases.
 */

static void
rectifyHavingClause(SelectStmt *stmt)
{
    HTAB *aliases;
    HASHCTL hashctl;
    ListCell *lc;

    hashctl.keysize = NAMEDATALEN;
    hashctl.entrysize = sizeof(AliasExpr);
    aliases = hash_create("Alias-Expre in target list", 
                          2048, 
                          &hashctl, 
                          HASH_ELEM | HASH_STRINGS);

    foreach (lc, stmt->targetList)
    {
        ResTarget *rt = (ResTarget *) lfirst(lc);
        if (rt->name != NULL)
        {
            bool found;
            AliasExpr *alaisExpr;
            alaisExpr = (AliasExpr *)hash_search(aliases, 
                                                 rt->name, 
                                                 HASH_ENTER, 
                                                 &found);
            if (!found)
            {
                alaisExpr->expr = rt->val;
            }
        }
    }

    rectifyHavingAlias(aliases, stmt->havingClause);
}

static void
rectifyHavingAlias(HTAB *aliases, Node *expr)
{
    /* 如果having中用的是自定义函数的别名，则最终结果与MySQl不同 */
    /* MySQL其实不允许这种情况： */
    /* Can't update table 'tab1' in stored function/trigger because it is already used by statement which invoked this stored function/trigger. */
    /* 实际中，having一般不会这么使用。 */
    if (IsA(expr, BoolExpr))
    {
		BoolExpr *blexpr;
        ListCell *lc;
		blexpr = castNode(BoolExpr, expr);
        foreach (lc, blexpr->args)
        {
            Node *node = lfirst(lc);
            rectifyHavingAlias(aliases, node);
        }
    }
    else 
    {
        if (IsA(expr, A_Expr))
        {
            A_Expr *aExpr = castNode(A_Expr, expr);
            Node *lNode = aExpr->lexpr;
            Node *rNode = aExpr->rexpr;
            if ((lNode != NULL) && IsA(lNode, ColumnRef))
            {
                ColumnRef *cr = castNode(ColumnRef, lNode);
                if (list_length(cr->fields) == 1)
                {
                    char *nm;
                    AliasExpr *aliasExpr;
                    bool found;
                    nm = strVal(linitial(cr->fields));
                    aliasExpr = (AliasExpr *)hash_search(aliases, 
                                                         nm,
                                                         HASH_FIND, 
                                                         &found);
                    if (found)
                    {
                        aExpr->lexpr = copyObject(aliasExpr->expr);
                    }
                }
            }
            if ((rNode != NULL) && IsA(rNode, ColumnRef))
            {
                ColumnRef *cr = castNode(ColumnRef, rNode);
                if (list_length(cr->fields) == 1)
                {
                    char *nm;
                    AliasExpr *aliasExpr;
                    bool found;
                    nm = strVal(linitial(cr->fields));
                    aliasExpr = (AliasExpr *)hash_search(aliases, 
                                                         nm,
                                                         HASH_FIND, 
                                                         &found);
                    if (found)
                    {
                        aExpr->rexpr = copyObject(aliasExpr->expr);
                    }
                }
            }
        }
        else if (IsA(expr, NullTest))
        {
            NullTest *nt = castNode(NullTest, expr);
            Node *node = (Node *)(nt->arg);
            if ((node != NULL) && IsA(node, ColumnRef))
            {
                ColumnRef *cr = castNode(ColumnRef, node);
                if (list_length(cr->fields) == 1)
                {
                    char *nm;
                    AliasExpr *aliasExpr;
                    bool found;
                    nm = strVal(linitial(cr->fields));
                    aliasExpr = (AliasExpr *)hash_search(aliases, 
                                                         nm,
                                                         HASH_FIND, 
                                                         &found);
                    if (found)
                    {
                        nt->arg = (Expr *)copyObject(aliasExpr->expr);
                    }
                }
            }
        }
        else if (IsA(expr, BooleanTest))
        {
            BooleanTest *bt = castNode(BooleanTest, expr);
            Node *node = (Node *)(bt->arg);
            if ((node != NULL) && IsA(node, ColumnRef))
            {
                ColumnRef *cr = castNode(ColumnRef, node);
                if (list_length(cr->fields) == 1)
                {
                    char *nm;
                    AliasExpr *aliasExpr;
                    bool found;
                    nm = strVal(linitial(cr->fields));
                    aliasExpr = (AliasExpr *)hash_search(aliases, 
                                                         nm,
                                                         HASH_FIND, 
                                                         &found);
                    if (found)
                    {
                        bt->arg = (Expr *)copyObject(aliasExpr->expr);
                    }
                }
            }
        }
        else if (IsA(expr, SubLink))
        {
            SubLink *sl = castNode(SubLink, expr);
            Node *node = sl->testexpr;
            if ((node != NULL) && IsA(node, ColumnRef))
            {
                ColumnRef *cr = castNode(ColumnRef, node);
                if (list_length(cr->fields) == 1)
                {
                    char *nm;
                    AliasExpr *aliasExpr;
                    bool found;
                    nm = strVal(linitial(cr->fields));
                    aliasExpr = (AliasExpr *)hash_search(aliases, 
                                                         nm,
                                                         HASH_FIND, 
                                                         &found);
                    if (found)
                    {
                        sl->testexpr = copyObject(aliasExpr->expr);
                    }
                }
            }
        }
    }
}

Query *
mys_transformSelectStmt(ParseState *pstate, SelectStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}



/*
 * standard_transformInsertStmt -
 *	  transform an Insert Statement
 */
Query *
mys_transformInsertStmt(ParseState *pstate, InsertStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}


Query *
mys_transformDeleteStmt(ParseState *pstate, DeleteStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}



static List *
retrieveSetTargets(List *totalTargetList, RangeVar *relation)
{
    List *targetList;
    ListCell *lc;
    int index;

    targetList = NIL;
    index = 1;
    foreach (lc, totalTargetList)
    {
        if ((index % 2) == 1)
        {
            char *targetRelName = NULL;
            int targetRelNameLen = 0;
            A_Const *rel;
            Node *node = lfirst(lc);
            // TODO: 还要判断schema
            if (!IsA(node, A_Const))
            {
                ereport(ERROR,
                        (errcode(ERRCODE_SYNTAX_ERROR),
                         errmsg("syntax error in table name or alias after set.")));
            }
            rel = castNode(A_Const, node);
			targetRelName = rel->val.sval.sval;
            targetRelNameLen = strlen(targetRelName);
            if (((targetRelNameLen == strlen(relation->relname)) && 
                 (strncasecmp(targetRelName, relation->relname, targetRelNameLen) == 0)) || 
                ((relation->alias!= NULL) && 
                 (relation->alias->aliasname != NULL) && 
                 (targetRelNameLen == strlen(relation->alias->aliasname)) && 
                 (strncasecmp(targetRelName, relation->alias->aliasname, targetRelNameLen) == 0)))
            {
                ListCell *subLc;
                int subIndex = 1;
                foreach (subLc, totalTargetList)
                {
                    if ((index + 1) == subIndex)
                    {
                        Node* resTarget = lfirst(subLc);
                        targetList = lappend(targetList, resTarget);
                        break;
                    }
                    ++subIndex;
                }
            }
        }
        ++index;
    }

    return targetList;
}


static Node *
mergeWhereClauseOnClause(Node *whereClause, Node *onClause)
{
    Node *newWhereClause;

    if (whereClause != NULL)
    {
        if (IsA(whereClause, BoolExpr))
        {
            BoolExpr *blexpr = (BoolExpr *)whereClause;
            if (blexpr->boolop == AND_EXPR)
            {
                blexpr->args = lappend(blexpr->args, onClause);
                newWhereClause = copyObject((Node *)blexpr);
            }
            else 
            {
                newWhereClause = (Node *)makeBoolExpr(AND_EXPR, 
                                                      list_make2(copyObject(whereClause), 
                                                                 copyObject(onClause)), 
                                                      -1);
            }
        }
        else 
        {
            newWhereClause = (Node *)makeBoolExpr(AND_EXPR, 
                                                  list_make2(copyObject(whereClause), 
                                                             copyObject(onClause)), 
                                                  -1);
        }
    }
    else
    {
        newWhereClause = copyObject(onClause);
    }

    return newWhereClause;
}


static void
rectifyExpr(RangeVar *relation, char *newVal, Node *expr)
{
    if ((expr != NULL) && (!IsA(expr, A_Const))) 
    {
        if (IsA(expr, ColumnRef))
        {
            // t2.name2 = t1.name1
            ColumnRef * columnRef = castNode(ColumnRef, expr);
            rectifyColumnRef(relation, newVal, columnRef);
        }
        else if (IsA(expr, FuncCall))
        {
            // t2.name2 = concat(t1.name1, t2.name2)
            FuncCall *funcCall = castNode(FuncCall, expr);
            ListCell *subLc;
            foreach (subLc, funcCall->args)
            {
                Node *nd = lfirst(subLc);
                rectifyExpr(relation, newVal, nd);
            }
        }
        else if (IsA(expr, A_Expr))
        {
            A_Expr * curExpr = castNode(A_Expr, expr);
            rectifyExpr(relation, newVal, curExpr->lexpr);
            rectifyExpr(relation, newVal, curExpr->rexpr);
        }
        else 
        {
            /* TODO: 可能还有更复杂的情况 */
        }
    }
}

static void
rectifyColumnRef(RangeVar *relation, char *newVal, ColumnRef *columnRef)
{
    // t2.name2 = t1.name1
    if (2 <= list_length(columnRef->fields))
    {
        char *relName = strVal(linitial(columnRef->fields));
        int relNameLen = strlen(relName);
        if (!(((relNameLen == strlen(relation->relname)) && 
               (strncasecmp(relName, relation->relname, relNameLen) == 0)) || 
              ((relation->alias != NULL) && 
               (relation->alias->aliasname != NULL) && 
               (relNameLen == strlen(relation->alias->aliasname)) && 
               (strncasecmp(relName, relation->alias->aliasname, relNameLen) == 0))))
        {
            String *val = linitial_node(String, columnRef->fields);
            val->sval = pstrdup(newVal);
        }
    }
}


static Query *
transformUpdateStmtToCte(ParseState *pstate, UpdateStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}



Query *
mys_transformUpdateStmt(ParseState *pstate, UpdateStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}


/*
 * transform a CallStmt
 */
Query *
mys_transformCallStmt(ParseState *pstate, CallStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}


static void
FindFirstType(ParseState *pstate, SelectStmt *stmt,
						  bool isTopLevel, List **targetlist)
{
    SelectStmt *StmtStack[100];
    int count = 0;
    bool isLeaf;
    bool isFirst = true;
    int targetNum = 0;
    ListCell   *tl;

    SelectStmt *root = copyObject(stmt);

    ParseState *ps = make_parsestate(pstate);
    ps->p_parent_cte = pstate->p_parent_cte;
    ps->p_locked_from_parent = false;
    ps->p_resolve_unknowns = false;

    while (root != NULL || count != 0)
    {
        while (root != NULL)
        {
            if (root->op == SETOP_NONE)
            {
                Assert(root->larg == NULL && root->rarg == NULL);
                isLeaf = true;
            }
            else
            {
                Assert(root->larg != NULL && root->rarg != NULL);
                if (root->sortClause || root->limitOffset || root->limitCount ||
                    root->lockingClause || root->withClause)
                    isLeaf = true;
                else
                    isLeaf = false;
            }

            if (isLeaf)
            {
                Query *selectQuery;
                char		selectName[32];
                // ParseNamespaceItem *nsitem;
                //RangeTblRef *rtr;
                ListCell   *subTl;
                List *targetList;
                int	next_resno;
                int temp_count=0;
                bool error = false;

                targetList = NULL;
                next_resno = 1;

                selectQuery = parse_sub_analyze((Node *) root, ps,
                                            NULL, false, false);

                    /*
                * Check for bogus references to Vars on the current query level (but
                * upper-level references are okay). Normally this can't happen
                * because the namespace will be empty, but it could happen if we are
                * inside a rule.
                */
                if (pstate->p_namespace)
                {
                    if (contain_vars_of_level((Node *) selectQuery, 1))
                        ereport(ERROR,
                                (errcode(ERRCODE_INVALID_COLUMN_REFERENCE),
                                errmsg("UNION/INTERSECT/EXCEPT member statement cannot refer to other relations of same query level"),
                                parser_errposition(pstate,
                                                    locate_var_of_level((Node *) selectQuery, 1))));
                }

                if (!isFirst)
                {
                    Assert(targetNum > 0);
                }

                foreach(subTl, selectQuery->targetList)
                {
                    TargetEntry *tle = (TargetEntry *) lfirst(subTl);
                    Node *colnode = (Node *) tle->expr;
                    Oid	coltype = exprType(colnode);

                    if (tle->resjunk)
                        continue;
                    
                    if (!error)
                    {
                        if (isFirst)
                        {
                            TargetEntry *tle_temp;
                            char *colname;

                            pstate->targettypelist = lappend_oid(pstate->targettypelist, coltype);

                            colname = pstrdup(tle->resname);
                            tle_temp = makeTargetEntry(tle->expr, next_resno++, colname, false);
                            targetList = lappend(targetList, tle_temp);
                        }
                        else
                        {
                            if (temp_count >= targetNum)
                            {
                                error = true;
                            }
                            else
                            {
                                if (list_nth_cell(pstate->targettypelist, temp_count)->oid_value == UNKNOWNOID)
                                {
                                    list_nth_cell(pstate->targettypelist, temp_count)->oid_value = coltype;
                                }
                            }
                        }
                    }

                    temp_count++;
                }

                if (error)
                {
                    ereport(ERROR,
                            (errcode(ERRCODE_SYNTAX_ERROR),
                             errmsg("each query must have the same number of columns %d, %d", 
                                    targetNum,
                                    temp_count)));
                }

                if (isFirst &&
                    ps->p_parent_cte &&
                    ps->p_parent_cte->cterecursive)
                {
                    analyzeCTETargetList(ps, ps->p_parent_cte, targetList);
                }

                if (isFirst)
                {
                    targetNum = list_length(pstate->targettypelist);
                    isFirst = false;
                }

                /*
                * Make the leaf query be a subquery in the top-level rangetable.
                */
                snprintf(selectName, sizeof(selectName), "*SELECT* %d",
                        list_length(ps->p_rtable) + 1);
                // nsitem = addRangeTableEntryForSubquery(ps,
                //                                     selectQuery,
                //                                     makeAlias(selectName, NIL),
                //                                     false,
                //                                     false);

                /*
                * Return a RangeTblRef to replace the SelectStmt in the set-op tree.
                */
                // rtr = makeNode(RangeTblRef);
                // rtr->rtindex = nsitem->p_rtindex;
                root = NULL;
            }
            else
            {
                if (root->rarg != NULL)
                {
                    StmtStack[count] = root->rarg;
                    count++;
                }
                root = root->larg;
            }
        }

        if (count > 0)
        {
            root = StmtStack[count-1];
            count--;
        }
    }

    tl = NULL;
    foreach (tl, pstate->targettypelist)
    {
        if (lfirst_oid(tl) == UNKNOWNOID)
        {
            lfirst_oid(tl) = TEXTOID;
        }
    }

    if (ps->p_parent_cte)
    {
        ps->p_parent_cte->ctecolnames = NULL;
        ps->p_parent_cte->ctecoltypes = NULL;
        ps->p_parent_cte->ctecoltypmods = NULL;
        ps->p_parent_cte->ctecolcollations = NULL;
    }

    free_parsestate(ps);

    return;
}

Query *
mys_transformSetOperationStmt(ParseState *pstate, SelectStmt *stmt)
{
	return transformStmt(pstate, (Node *) stmt); /* M3: delegate to PG18 */
}


/*
 * select_common_type()
 *		Determine the common supertype of a list of input expressions.
 *		This is used for determining the output type of CASE, UNION,
 *		and similar constructs.
 *
 * 'exprs' is a *nonempty* list of expressions.  Note that earlier items
 * in the list will be preferred if there is doubt.
 * 'context' is a phrase to use in the error message if we fail to select
 * a usable type.  Pass NULL to have the routine return InvalidOid
 * rather than throwing an error on failure.
 * 'which_expr': if not NULL, receives a pointer to the particular input
 * expression from which the result type was taken.
 *
 * Caution: "failure" just means that there were inputs of different type
 * categories.  It is not guaranteed that all the inputs are coercible to the
 * selected type; caller must check that (see verify_common_type).
 */
static Oid
mys_select_common_type(ParseState *pstate, List *exprs, const char *context,
                       Node **which_expr)
{
    if ((context != NULL) && 
        ((strcmp(context, "UNION") == 0) || 
         (strcmp(context, "INTERSECT") == 0) || 
         (strcmp(context, "EXCEPT") == 0)))
    {
        Node *lexpr;
        Oid	ltype;
        Node *rexpr;
        Oid	rtype;

        Assert(exprs != NIL);
        lexpr = (Node *) linitial(exprs);
        ltype = exprType(lexpr);
        ltype = getBaseType(ltype);
        rexpr = (Node *) lsecond(exprs);
        rtype = exprType(rexpr);
        rtype = getBaseType(rtype);
        if (((ltype == UNKNOWNOID) && IsA(lexpr, Const) && !(((Const *)lexpr)->constisnull)) && 
            ((rtype == UNKNOWNOID) && IsA(rexpr, Const) && !(((Const *)rexpr)->constisnull)))
        {
			if (which_expr)
				*which_expr = lexpr;
            return TEXTOID;
        }
        else if ((ltype == UNKNOWNOID) && IsA(lexpr, Const) && !(((Const *)lexpr)->constisnull))
        {
			if (which_expr)
				*which_expr = rexpr;
            return TEXTOID;
        }
        else if ((rtype == UNKNOWNOID) && IsA(rexpr, Const) && !(((Const *)rexpr)->constisnull))
        {
			if (which_expr)
				*which_expr = lexpr;
            return TEXTOID;
        }
        else 
        {
            if (((ltype == TEXTOID) || (ltype == VARCHAROID) || (ltype == BPCHAROID)) && (rtype != UNKNOWNOID))
            {
                if (which_expr)
                    *which_expr = rexpr;
                return TEXTOID;
            }
            else if (((rtype == TEXTOID) || (rtype == VARCHAROID) || (rtype == BPCHAROID)) && (ltype != UNKNOWNOID))
            {
                if (which_expr)
                    *which_expr = lexpr;
                return TEXTOID;
            }
            else 
            {
                Node	   *pexpr;
                Oid			ptype;
                TYPCATEGORY pcategory;
                bool		pispreferred;
                ListCell   *lc;

                Assert(exprs != NIL);
                pexpr = (Node *) linitial(exprs);
                lc = list_second_cell(exprs);
                ptype = exprType(pexpr);

                /*
                 * If all input types are valid and exactly the same, just pick that type.
                 * This is the only way that we will resolve the result as being a domain
                 * type; otherwise domains are smashed to their base types for comparison.
                 */
                if (ptype != UNKNOWNOID)
                {
                    for_each_cell(lc, exprs, lc)
                    {
                        Node	   *nexpr = (Node *) lfirst(lc);
                        Oid			ntype = exprType(nexpr);

                        if (ntype != ptype)
                            break;
                    }
                    if (lc == NULL)			/* got to the end of the list? */
                    {
                        if (which_expr)
                            *which_expr = pexpr;
                        return ptype;
                    }
                }

                /*
                 * Nope, so set up for the full algorithm.  Note that at this point, lc
                 * points to the first list item with type different from pexpr's; we need
                 * not re-examine any items the previous loop advanced over.
                 */
                ptype = getBaseType(ptype);
                get_type_category_preferred(ptype, &pcategory, &pispreferred);

                for_each_cell(lc, exprs, lc)
                {
                    Node	   *nexpr = (Node *) lfirst(lc);
                    Oid			ntype = getBaseType(exprType(nexpr));

                    /* move on to next one if no new information... */
                    if (ntype != UNKNOWNOID && ntype != ptype)
                    {
                        TYPCATEGORY ncategory;
                        bool		nispreferred;

                        get_type_category_preferred(ntype, &ncategory, &nispreferred);
                        if (ptype == UNKNOWNOID)
                        {
                            /* so far, only unknowns so take anything... */
                            pexpr = nexpr;
                            ptype = ntype;
                            pcategory = ncategory;
                            pispreferred = nispreferred;
                        }
                        else if (ncategory != pcategory)
                        {
                            /*
                             * both types in different categories? then not much hope...
                             */
                            if (context == NULL)
                                return InvalidOid;

                            /* 针对一下union情况做特别处理：*/
                            /* select distinct null as abc union select col from tab_u; */
                            /* select id from tab_u union select distinct null as abc; */
                            /* 以下报错先注释掉 */
                            //ereport(ERROR,
                            //		(errcode(ERRCODE_DATATYPE_MISMATCH),
                            ///*------
                            //  translator: first %s is name of a SQL construct, eg CASE */
                            //		 errmsg("%s types %s and %s cannot be matched",
                            //				context,
                            //				format_type_be(ptype),
                            //				format_type_be(ntype)),
                            //		 parser_errposition(pstate, exprLocation(nexpr))));
                            if (strncasecmp(context, "UNION", 5) == 0) 
                            {
                                if (IsA(pexpr, Const) && (((Const *)pexpr)->constisnull))
                                {
                                    ((Const *)pexpr)->consttype = ntype;
                                    ptype = ntype;
                                }
                                else if (IsA(nexpr, Const) && (((Const *)nexpr)->constisnull))
                                {
                                    ((Const *)nexpr)->consttype = ptype;
                                }
                                else 
                                {
                                    if (((((ptype == INT4OID) || (ptype == INT2OID) || (ptype == INT8OID)) && 
                                          ((ntype == TEXTOID) || (ntype == BPCHAROID) || (ntype == VARCHAROID))) || 
                                         (((ntype == INT4OID) || (ntype == INT2OID) || (ntype == INT8OID)) && 
                                          ((ptype == TEXTOID) || (ptype == BPCHAROID) || (ptype == VARCHAROID)))) || 
                                        (((ptype == TIMEOID) || (ptype == DATEOID) || (ptype == TIMESTAMPOID) || (ptype == TIMESTAMPTZOID)) && 
                                         ((ntype == TEXTOID) || (ntype == BPCHAROID) || (ntype == VARCHAROID))))
                                    {
                                        ptype = TEXTOID;
                                        ntype = TEXTOID;
                                    }
                                }
                            }
                            else 
                            {
                                ereport(ERROR,
                                        (errcode(ERRCODE_DATATYPE_MISMATCH),
                                         /*------
                                           translator: first %s is name of a SQL construct, eg CASE */
                                         errmsg("%s types %s and %s cannot be matched",
                                                context,
                                                format_type_be(ptype),
                                                format_type_be(ntype)),
                                         parser_errposition(pstate, exprLocation(nexpr))));
                            }
                        }
                        else if (!pispreferred &&
                                 can_coerce_type(1, &ptype, &ntype, COERCION_IMPLICIT) &&
                                 !can_coerce_type(1, &ntype, &ptype, COERCION_IMPLICIT))
                        {
                            /*
                             * take new type if can coerce to it implicitly but not the
                             * other way; but if we have a preferred type, stay on it.
                             */
                            pexpr = nexpr;
                            ptype = ntype;
                            pcategory = ncategory;
                            pispreferred = nispreferred;
                        }
                    }
                }

                /*
                 * If all the inputs were UNKNOWN type --- ie, unknown-type literals ---
                 * then resolve as type TEXT.  This situation comes up with constructs
                 * like SELECT (CASE WHEN foo THEN 'bar' ELSE 'baz' END); SELECT 'foo'
                 * UNION SELECT 'bar'; It might seem desirable to leave the construct's
                 * output type as UNKNOWN, but that really doesn't work, because we'd
                 * probably end up needing a runtime coercion from UNKNOWN to something
                 * else, and we usually won't have it.  We need to coerce the unknown
                 * literals while they are still literals, so a decision has to be made
                 * now.
                 */
                // if (ptype == UNKNOWNOID)
                // 	ptype = TEXTOID;
                
                if ((context != NULL) && 
                    ((strcmp(context, "UNION") == 0) || 
                     (strcmp(context, "INTERSECT") == 0) || 
                     (strcmp(context, "EXCEPT") == 0)))
                {
                    if (ptype == UNKNOWNOID)
                        ptype = UNKNOWNOID;
                }
                else
                {
                    if (ptype == UNKNOWNOID)
                        ptype = TEXTOID;
                }
                

                if (which_expr)
                    *which_expr = pexpr;
                return ptype;
            }
        }
    }
    else 
    {
        Node	   *pexpr;
        Oid			ptype;
        TYPCATEGORY pcategory;
        bool		pispreferred;
        ListCell   *lc;

        Assert(exprs != NIL);
        pexpr = (Node *) linitial(exprs);
        lc = list_second_cell(exprs);
        ptype = exprType(pexpr);

        /*
         * If all input types are valid and exactly the same, just pick that type.
         * This is the only way that we will resolve the result as being a domain
         * type; otherwise domains are smashed to their base types for comparison.
         */
        if (ptype != UNKNOWNOID)
        {
            for_each_cell(lc, exprs, lc)
            {
                Node	   *nexpr = (Node *) lfirst(lc);
                Oid			ntype = exprType(nexpr);

                if (ntype != ptype)
                    break;
            }
            if (lc == NULL)			/* got to the end of the list? */
            {
                if (which_expr)
                    *which_expr = pexpr;
                return ptype;
            }
        }

        /*
         * Nope, so set up for the full algorithm.  Note that at this point, lc
         * points to the first list item with type different from pexpr's; we need
         * not re-examine any items the previous loop advanced over.
         */
        ptype = getBaseType(ptype);
        get_type_category_preferred(ptype, &pcategory, &pispreferred);

        for_each_cell(lc, exprs, lc)
        {
            Node	   *nexpr = (Node *) lfirst(lc);
            Oid			ntype = getBaseType(exprType(nexpr));

            /* move on to next one if no new information... */
            if (ntype != UNKNOWNOID && ntype != ptype)
            {
                TYPCATEGORY ncategory;
                bool		nispreferred;

                get_type_category_preferred(ntype, &ncategory, &nispreferred);
                if (ptype == UNKNOWNOID)
                {
                    /* so far, only unknowns so take anything... */
                    pexpr = nexpr;
                    ptype = ntype;
                    pcategory = ncategory;
                    pispreferred = nispreferred;
                }
                else if (ncategory != pcategory)
                {
                    /*
                     * both types in different categories? then not much hope...
                     */
                    if (context == NULL)
                        return InvalidOid;

                    /* 针对一下union情况做特别处理：*/
                    /* select distinct null as abc union select col from tab_u; */
                    /* select id from tab_u union select distinct null as abc; */
                    /* 以下报错先注释掉 */
                    //ereport(ERROR,
                    //		(errcode(ERRCODE_DATATYPE_MISMATCH),
                    ///*------
                    //  translator: first %s is name of a SQL construct, eg CASE */
                    //		 errmsg("%s types %s and %s cannot be matched",
                    //				context,
                    //				format_type_be(ptype),
                    //				format_type_be(ntype)),
                    //		 parser_errposition(pstate, exprLocation(nexpr))));
                    if (strncasecmp(context, "UNION", 5) == 0) 
                    {
                        if (IsA(pexpr, Const) && (((Const *)pexpr)->constisnull))
                        {
                            ((Const *)pexpr)->consttype = ntype;
                            ptype = ntype;
                        }
                        else if (IsA(nexpr, Const) && (((Const *)nexpr)->constisnull))
                        {
                            ((Const *)nexpr)->consttype = ptype;
                        }
                        else 
                        {
                            if (((((ptype == INT4OID) || (ptype == INT2OID) || (ptype == INT8OID)) && 
                                  ((ntype == TEXTOID) || (ntype == BPCHAROID) || (ntype == VARCHAROID))) || 
                                 (((ntype == INT4OID) || (ntype == INT2OID) || (ntype == INT8OID)) && 
                                  ((ptype == TEXTOID) || (ptype == BPCHAROID) || (ptype == VARCHAROID)))) || 
                                (((ptype == TIMEOID) || (ptype == DATEOID) || (ptype == TIMESTAMPOID) || (ptype == TIMESTAMPTZOID)) && 
                                 ((ntype == TEXTOID) || (ntype == BPCHAROID) || (ntype == VARCHAROID))))
                            {
                                ptype = TEXTOID;
                                ntype = TEXTOID;
                            }
                        }
                    }
                    else 
                    {
                        ereport(ERROR,
                                (errcode(ERRCODE_DATATYPE_MISMATCH),
                                 /*------
                                   translator: first %s is name of a SQL construct, eg CASE */
                                 errmsg("%s types %s and %s cannot be matched",
                                        context,
                                        format_type_be(ptype),
                                        format_type_be(ntype)),
                                 parser_errposition(pstate, exprLocation(nexpr))));
                    }
                }
                else if (!pispreferred &&
                         can_coerce_type(1, &ptype, &ntype, COERCION_IMPLICIT) &&
                         !can_coerce_type(1, &ntype, &ptype, COERCION_IMPLICIT))
                {
                    /*
                     * take new type if can coerce to it implicitly but not the
                     * other way; but if we have a preferred type, stay on it.
                     */
                    pexpr = nexpr;
                    ptype = ntype;
                    pcategory = ncategory;
                    pispreferred = nispreferred;
                }
            }
        }

        /*
         * If all the inputs were UNKNOWN type --- ie, unknown-type literals ---
         * then resolve as type TEXT.  This situation comes up with constructs
         * like SELECT (CASE WHEN foo THEN 'bar' ELSE 'baz' END); SELECT 'foo'
         * UNION SELECT 'bar'; It might seem desirable to leave the construct's
         * output type as UNKNOWN, but that really doesn't work, because we'd
         * probably end up needing a runtime coercion from UNKNOWN to something
         * else, and we usually won't have it.  We need to coerce the unknown
         * literals while they are still literals, so a decision has to be made
         * now.
         */
        // if (ptype == UNKNOWNOID)
        // 	ptype = TEXTOID;
        
        if ((context != NULL) && 
            ((strcmp(context, "UNION") == 0) || 
             (strcmp(context, "INTERSECT") == 0) || 
             (strcmp(context, "EXCEPT") == 0)))
        {
            if (ptype == UNKNOWNOID)
                ptype = UNKNOWNOID;
        }
        else
        {
            if (ptype == UNKNOWNOID)
                ptype = TEXTOID;
        }
        

        if (which_expr)
            *which_expr = pexpr;
        return ptype;
    }
}

/*
 * mys_transformSetOperationTree
 *		Recursively transform leaves and internal nodes of a set-op tree
 *
 * In addition to returning the transformed node, if targetlist isn't NULL
 * then we return a list of its non-resjunk TargetEntry nodes.  For a leaf
 * set-op node these are the actual targetlist entries; otherwise they are
 * dummy entries created to carry the type, typmod, collation, and location
 * (for error messages) of each output column of the set-op node.  This info
 * is needed only during the internal recursion of this function, so outside
 * callers pass NULL for targetlist.  Note: the reason for passing the
 * actual targetlist entries of a leaf node is so that upper levels can
 * replace UNKNOWN Consts with properly-coerced constants.
 */
Node *
mys_transformSetOperationTree(ParseState *pstate, SelectStmt *stmt,
                              bool isTopLevel, List **targetlist)
{
	return NULL; /* M3: use standard PG18 set-op tree handling */
}


/*
 * Process the outputs of the non-recursive term of a recursive union
 * to set up the parent CTE's columns
 */
static void
determineRecursiveColTypes(ParseState *pstate, Node *larg, List *nrtargetlist)
{
	Node	   *node;
	int			leftmostRTI;
	Query	   *leftmostQuery;
	List	   *targetList;
	ListCell   *left_tlist;
	ListCell   *nrtl;
	int			next_resno;

	/*
	 * Find leftmost leaf SELECT
	 */
	node = larg;
	while (node && IsA(node, SetOperationStmt))
		node = ((SetOperationStmt *) node)->larg;
	Assert(node && IsA(node, RangeTblRef));
	leftmostRTI = ((RangeTblRef *) node)->rtindex;
	leftmostQuery = rt_fetch(leftmostRTI, pstate->p_rtable)->subquery;
	Assert(leftmostQuery != NULL);

	/*
	 * Generate dummy targetlist using column names of leftmost select and
	 * dummy result expressions of the non-recursive term.
	 */
	targetList = NIL;
	next_resno = 1;

	forboth(nrtl, nrtargetlist, left_tlist, leftmostQuery->targetList)
	{
		TargetEntry *nrtle = (TargetEntry *) lfirst(nrtl);
		TargetEntry *lefttle = (TargetEntry *) lfirst(left_tlist);
		char	   *colName;
		TargetEntry *tle;

		Assert(!lefttle->resjunk);
		colName = pstrdup(lefttle->resname);
		tle = makeTargetEntry(nrtle->expr,
							  next_resno++,
							  colName,
							  false);
		targetList = lappend(targetList, tle);
	}

	/* Now build CTE's output column info using dummy targetlist */
	analyzeCTETargetList(pstate, pstate->p_parent_cte, targetList);
}


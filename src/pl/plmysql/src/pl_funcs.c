/*-------------------------------------------------------------------------
 *
 * pl_funcs.c		- Misc functions for the PL/MySQL
 *			  procedural language
 *
 * Portions Copyright (c) 2026, Halo Tech Co.,Ltd.
 * Portions Copyright (c) 1996-2021, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/pl/plmysql/src/pl_funcs.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "plmysql.h"
#include "utils/memutils.h"

/* ----------
 * Local variables for namespace handling
 *
 * The namespace structure actually forms a tree, of which only one linear
 * list or "chain" (from the youngest item to the root) is accessible from
 * any one plmysql statement.  During initial parsing of a function, ns_top
 * points to the youngest item accessible from the block currently being
 * parsed.  We store the entire tree, however, since at runtime we will need
 * to access the chain that's relevant to any one statement.
 *
 * Block boundaries in the namespace chain are marked by PLMYSQL_NSTYPE_LABEL
 * items.
 * ----------
 */
static PLMySQL_nsitem *ns_top = NULL;


/* ----------
 * plmysql_ns_init			Initialize namespace processing for a new function
 * ----------
 */
void
plmysql_ns_init(void)
{
	ns_top = NULL;
}


/* ----------
 * plmysql_ns_push			Create a new namespace level
 * ----------
 */
void
plmysql_ns_push(const char *label, PLMySQL_label_type label_type)
{
	if (label == NULL)
		label = "";
	plmysql_ns_additem(PLMYSQL_NSTYPE_LABEL, (int) label_type, label);
}


/* ----------
 * plmysql_ns_pop			Pop entries back to (and including) the last label
 * ----------
 */
void
plmysql_ns_pop(void)
{
	Assert(ns_top != NULL);
	while (ns_top->itemtype != PLMYSQL_NSTYPE_LABEL)
		ns_top = ns_top->prev;
	ns_top = ns_top->prev;
}


/* ----------
 * plmysql_ns_top			Fetch the current namespace chain end
 * ----------
 */
PLMySQL_nsitem *
plmysql_ns_top(void)
{
	return ns_top;
}


/* ----------
 * plmysql_ns_additem		Add an item to the current namespace chain
 * ----------
 */
void
plmysql_ns_additem(PLMySQL_nsitem_type itemtype, int itemno, const char *name)
{
	PLMySQL_nsitem *nse;

	Assert(name != NULL);
	/* first item added must be a label */
	Assert(ns_top != NULL || itemtype == PLMYSQL_NSTYPE_LABEL);

	nse = palloc(offsetof(PLMySQL_nsitem, name) + strlen(name) + 1);
	nse->itemtype = itemtype;
	nse->itemno = itemno;
	nse->prev = ns_top;
	strcpy(nse->name, name);
	ns_top = nse;
}


/* ----------
 * plmysql_ns_lookup		Lookup an identifier in the given namespace chain
 *
 * Note that this only searches for variables, not labels.
 *
 * If localmode is true, only the topmost block level is searched.
 *
 * name1 must be non-NULL.  Pass NULL for name2 and/or name3 if parsing a name
 * with fewer than three components.
 *
 * If names_used isn't NULL, *names_used receives the number of names
 * matched: 0 if no match, 1 if name1 matched an unqualified variable name,
 * 2 if name1 and name2 matched a block label + variable name.
 *
 * Note that name3 is never directly matched to anything.  However, if it
 * isn't NULL, we will disregard qualified matches to scalar variables.
 * Similarly, if name2 isn't NULL, we disregard unqualified matches to
 * scalar variables.
 * ----------
 */
PLMySQL_nsitem *
plmysql_ns_lookup(PLMySQL_nsitem *ns_cur, bool localmode,
				  const char *name1, const char *name2, const char *name3,
				  int *names_used)
{
	/* Outer loop iterates once per block level in the namespace chain */
	while (ns_cur != NULL)
	{
		PLMySQL_nsitem *nsitem;

		/* Check this level for unqualified match to variable name */
		for (nsitem = ns_cur;
			 nsitem->itemtype != PLMYSQL_NSTYPE_LABEL;
			 nsitem = nsitem->prev)
		{
			if (strcmp(nsitem->name, name1) == 0)
			{
				if (name2 == NULL ||
					nsitem->itemtype != PLMYSQL_NSTYPE_VAR)
				{
					if (names_used)
						*names_used = 1;
					return nsitem;
				}
			}
		}

		/* Check this level for qualified match to variable name */
		if (name2 != NULL &&
			strcmp(nsitem->name, name1) == 0)
		{
			for (nsitem = ns_cur;
				 nsitem->itemtype != PLMYSQL_NSTYPE_LABEL;
				 nsitem = nsitem->prev)
			{
				if (strcmp(nsitem->name, name2) == 0)
				{
					if (name3 == NULL ||
						nsitem->itemtype != PLMYSQL_NSTYPE_VAR)
					{
						if (names_used)
							*names_used = 2;
						return nsitem;
					}
				}
			}
		}

		if (localmode)
			break;				/* do not look into upper levels */

		ns_cur = nsitem->prev;
	}

	/* This is just to suppress possibly-uninitialized-variable warnings */
	if (names_used)
		*names_used = 0;
	return NULL;				/* No match found */
}


/* ----------
 * plmysql_ns_lookup_label		Lookup a label in the given namespace chain
 * ----------
 */
PLMySQL_nsitem *
plmysql_ns_lookup_label(PLMySQL_nsitem *ns_cur, const char *name)
{
	while (ns_cur != NULL)
	{
		if (ns_cur->itemtype == PLMYSQL_NSTYPE_LABEL &&
			strcmp(ns_cur->name, name) == 0)
			return ns_cur;
		ns_cur = ns_cur->prev;
	}

	return NULL;				/* label not found */
}


/* ----------
 * plmysql_ns_find_nearest_loop		Find innermost loop label in namespace chain
 * ----------
 */
PLMySQL_nsitem *
plmysql_ns_find_nearest_loop(PLMySQL_nsitem *ns_cur)
{
	while (ns_cur != NULL)
	{
		if (ns_cur->itemtype == PLMYSQL_NSTYPE_LABEL &&
			ns_cur->itemno == PLMYSQL_LABEL_LOOP)
			return ns_cur;
		ns_cur = ns_cur->prev;
	}

	return NULL;				/* no loop found */
}


/*
 * Statement type as a string, for use in error messages etc.
 */
const char *
plmysql_stmt_typename(PLMySQL_stmt *stmt)
{
	switch (stmt->cmd_type)
	{
		case PLMYSQL_STMT_BLOCK:
			return _("statement block");
		case PLMYSQL_STMT_ASSIGN:
			return _("assignment");
		case PLMYSQL_STMT_IF:
			return "IF";
		case PLMYSQL_STMT_CASE:
			return "CASE";
		case PLMYSQL_STMT_LOOP:
			return "LOOP";
		case PLMYSQL_STMT_WHILE:
			return "WHILE";
		case PLMYSQL_STMT_EXIT:
			return ((PLMySQL_stmt_exit *) stmt)->is_exit ? "EXIT" : "CONTINUE";
		case PLMYSQL_STMT_RETURN:
			return "RETURN";
		case PLMYSQL_STMT_RETURN_NEXT:
			return "RETURN NEXT";
		case PLMYSQL_STMT_RETURN_QUERY:
			return "RETURN QUERY";
		case PLMYSQL_STMT_RAISE:
			return "RAISE";
		case PLMYSQL_STMT_SIGNAL:
			return ((PLMySQL_stmt_signal *) stmt)->is_resignal ? "RESIGNAL" : "SIGNAL";
		case PLMYSQL_STMT_ASSERT:
			return "ASSERT";
		case PLMYSQL_STMT_EXECSQL:
			return _("SQL statement");
		case PLMYSQL_STMT_DYNEXECUTE:
			return "EXECUTE";
		case PLMYSQL_STMT_GETDIAG:
			return ((PLMySQL_stmt_getdiag *) stmt)->is_stacked ?
				"GET STACKED DIAGNOSTICS" : "GET DIAGNOSTICS";
		case PLMYSQL_STMT_OPEN:
			return "OPEN";
		case PLMYSQL_STMT_FETCH:
			return ((PLMySQL_stmt_fetch *) stmt)->is_move ? "MOVE" : "FETCH";
		case PLMYSQL_STMT_CLOSE:
			return "CLOSE";
		case PLMYSQL_STMT_PERFORM:
			return "PERFORM";
		case PLMYSQL_STMT_CALL:
			return ((PLMySQL_stmt_call *) stmt)->is_call ? "CALL" : "DO";
		case PLMYSQL_STMT_COMMIT:
			return "COMMIT";
		case PLMYSQL_STMT_ROLLBACK:
			return "ROLLBACK";
		case PLMYSQL_STMT_START:
			return "START TRANSACTION";
		case PLMYSQL_STMT_SAVEPOINT:
			return "SAVEPOINT";
		case PLMYSQL_STMT_ROLLBACK_TO:
			return "ROLLBACK TO SAVEPOINT";
		case PLMYSQL_STMT_RELEASE_SAVEPOINT:
			return "RELEASE SAVEPOINT";
	}

	return "unknown";
}

/*
 * GET DIAGNOSTICS item name as a string, for use in error messages etc.
 */
const char *
plmysql_getdiag_kindname(PLMySQL_getdiag_kind kind)
{
	switch (kind)
	{
		case PLMYSQL_GETDIAG_ROW_COUNT:
			return "ROW_COUNT";
		case PLMYSQL_GETDIAG_RETURNED_SQLSTATE:
			return "RETURNED_SQLSTATE";
		case PLMYSQL_GETDIAG_COLUMN_NAME:
			return "COLUMN_NAME";
		case PLMYSQL_GETDIAG_CONSTRAINT_NAME:
			return "CONSTRAINT_NAME";
		case PLMYSQL_GETDIAG_MESSAGE_TEXT:
			return "MESSAGE_TEXT";
		case PLMYSQL_GETDIAG_TABLE_NAME:
			return "TABLE_NAME";
		case PLMYSQL_GETDIAG_SCHEMA_NAME:
			return "SCHEMA_NAME";
		case PLMYSQL_GETDIAG_MYSQL_ERRNO:
			return "MYSQL_ERRNO";
	}

	return "unknown";
}


/**********************************************************************
 * Release memory when a PL/MySQL function is no longer needed
 *
 * The code for recursing through the function tree is really only
 * needed to locate PLMySQL_expr nodes, which may contain references
 * to saved SPI Plans that must be freed.  The function tree itself,
 * along with subsidiary data, is freed in one swoop by freeing the
 * function's permanent memory context.
 **********************************************************************/
static void free_stmt(PLMySQL_stmt *stmt);
static void free_block(PLMySQL_stmt_block *block);
static void free_assign(PLMySQL_stmt_assign *stmt);
static void free_if(PLMySQL_stmt_if *stmt);
static void free_case(PLMySQL_stmt_case *stmt);
static void free_loop(PLMySQL_stmt_loop *stmt);
static void free_while(PLMySQL_stmt_while *stmt);
static void free_exit(PLMySQL_stmt_exit *stmt);
static void free_return(PLMySQL_stmt_return *stmt);
static void free_return_next(PLMySQL_stmt_return_next *stmt);
static void free_return_query(PLMySQL_stmt_return_query *stmt);
static void free_raise(PLMySQL_stmt_raise *stmt);
static void free_assert(PLMySQL_stmt_assert *stmt);
static void free_execsql(PLMySQL_stmt_execsql *stmt);
static void free_dynexecute(PLMySQL_stmt_dynexecute *stmt);
static void free_getdiag(PLMySQL_stmt_getdiag *stmt);
static void free_open(PLMySQL_stmt_open *stmt);
static void free_fetch(PLMySQL_stmt_fetch *stmt);
static void free_close(PLMySQL_stmt_close *stmt);
static void free_perform(PLMySQL_stmt_perform *stmt);
static void free_call(PLMySQL_stmt_call *stmt);
static void free_commit(PLMySQL_stmt_commit *stmt);
static void free_rollback(PLMySQL_stmt_rollback *stmt);
static void free_expr(PLMySQL_expr *expr);


static void
free_stmt(PLMySQL_stmt *stmt)
{
	switch (stmt->cmd_type)
	{
		case PLMYSQL_STMT_BLOCK:
			free_block((PLMySQL_stmt_block *) stmt);
			break;
		case PLMYSQL_STMT_ASSIGN:
			free_assign((PLMySQL_stmt_assign *) stmt);
			break;
		case PLMYSQL_STMT_IF:
			free_if((PLMySQL_stmt_if *) stmt);
			break;
		case PLMYSQL_STMT_CASE:
			free_case((PLMySQL_stmt_case *) stmt);
			break;
		case PLMYSQL_STMT_LOOP:
			free_loop((PLMySQL_stmt_loop *) stmt);
			break;
		case PLMYSQL_STMT_WHILE:
			free_while((PLMySQL_stmt_while *) stmt);
			break;
		case PLMYSQL_STMT_EXIT:
			free_exit((PLMySQL_stmt_exit *) stmt);
			break;
		case PLMYSQL_STMT_RETURN:
			free_return((PLMySQL_stmt_return *) stmt);
			break;
		case PLMYSQL_STMT_RETURN_NEXT:
			free_return_next((PLMySQL_stmt_return_next *) stmt);
			break;
		case PLMYSQL_STMT_RETURN_QUERY:
			free_return_query((PLMySQL_stmt_return_query *) stmt);
			break;
		case PLMYSQL_STMT_RAISE:
			free_raise((PLMySQL_stmt_raise *) stmt);
			break;
		case PLMYSQL_STMT_SIGNAL:
			/* nothing extra to free: sqlstate is shared, items are exprs */
			break;
		case PLMYSQL_STMT_ASSERT:
			free_assert((PLMySQL_stmt_assert *) stmt);
			break;
		case PLMYSQL_STMT_EXECSQL:
			free_execsql((PLMySQL_stmt_execsql *) stmt);
			break;
		case PLMYSQL_STMT_DYNEXECUTE:
			free_dynexecute((PLMySQL_stmt_dynexecute *) stmt);
			break;
		case PLMYSQL_STMT_GETDIAG:
			free_getdiag((PLMySQL_stmt_getdiag *) stmt);
			break;
		case PLMYSQL_STMT_OPEN:
			free_open((PLMySQL_stmt_open *) stmt);
			break;
		case PLMYSQL_STMT_FETCH:
			free_fetch((PLMySQL_stmt_fetch *) stmt);
			break;
		case PLMYSQL_STMT_CLOSE:
			free_close((PLMySQL_stmt_close *) stmt);
			break;
		case PLMYSQL_STMT_PERFORM:
			free_perform((PLMySQL_stmt_perform *) stmt);
			break;
		case PLMYSQL_STMT_CALL:
			free_call((PLMySQL_stmt_call *) stmt);
			break;
		case PLMYSQL_STMT_COMMIT:
			free_commit((PLMySQL_stmt_commit *) stmt);
			break;
		case PLMYSQL_STMT_ROLLBACK:
			free_rollback((PLMySQL_stmt_rollback *) stmt);
			break;
		case PLMYSQL_STMT_START:
		case PLMYSQL_STMT_SAVEPOINT:
		case PLMYSQL_STMT_ROLLBACK_TO:
		case PLMYSQL_STMT_RELEASE_SAVEPOINT:
			/* no separately-allocated storage worth chasing */
			break;
		default:
			elog(ERROR, "unrecognized cmd_type: %d", stmt->cmd_type);
			break;
	}
}

static void
free_stmts(List *stmts)
{
	ListCell   *s;

	foreach(s, stmts)
	{
		free_stmt((PLMySQL_stmt *) lfirst(s));
	}
}

static void
free_block(PLMySQL_stmt_block *block)
{
	free_stmts(block->body);
	if (block->exceptions)
	{
		ListCell   *e;

		foreach(e, block->exceptions->exc_list)
		{
			PLMySQL_exception *exc = (PLMySQL_exception *) lfirst(e);

			free_stmts(exc->action);
		}
	}
}

static void
free_assign(PLMySQL_stmt_assign *stmt)
{
	free_expr(stmt->expr);
}

static void
free_if(PLMySQL_stmt_if *stmt)
{
	ListCell   *l;

	free_expr(stmt->cond);
	free_stmts(stmt->then_body);
	foreach(l, stmt->elsif_list)
	{
		PLMySQL_if_elsif *elif = (PLMySQL_if_elsif *) lfirst(l);

		free_expr(elif->cond);
		free_stmts(elif->stmts);
	}
	free_stmts(stmt->else_body);
}

static void
free_case(PLMySQL_stmt_case *stmt)
{
	ListCell   *l;

	free_expr(stmt->t_expr);
	foreach(l, stmt->case_when_list)
	{
		PLMySQL_case_when *cwt = (PLMySQL_case_when *) lfirst(l);

		free_expr(cwt->expr);
		free_stmts(cwt->stmts);
	}
	free_stmts(stmt->else_stmts);
}

static void
free_loop(PLMySQL_stmt_loop *stmt)
{
	free_stmts(stmt->body);
}

static void
free_while(PLMySQL_stmt_while *stmt)
{
	free_expr(stmt->cond);
	free_stmts(stmt->body);
}

static void
free_open(PLMySQL_stmt_open *stmt)
{
	ListCell   *lc;

	free_expr(stmt->argquery);
	free_expr(stmt->query);
	free_expr(stmt->dynquery);
	foreach(lc, stmt->params)
	{
		free_expr((PLMySQL_expr *) lfirst(lc));
	}
}

static void
free_fetch(PLMySQL_stmt_fetch *stmt)
{
	free_expr(stmt->expr);
}

static void
free_close(PLMySQL_stmt_close *stmt)
{
}

static void
free_perform(PLMySQL_stmt_perform *stmt)
{
	free_expr(stmt->expr);
}

static void
free_call(PLMySQL_stmt_call *stmt)
{
	free_expr(stmt->expr);
}

static void
free_commit(PLMySQL_stmt_commit *stmt)
{
}

static void
free_rollback(PLMySQL_stmt_rollback *stmt)
{
}

static void
free_exit(PLMySQL_stmt_exit *stmt)
{
	free_expr(stmt->cond);
}

static void
free_return(PLMySQL_stmt_return *stmt)
{
	free_expr(stmt->expr);
}

static void
free_return_next(PLMySQL_stmt_return_next *stmt)
{
	free_expr(stmt->expr);
}

static void
free_return_query(PLMySQL_stmt_return_query *stmt)
{
	ListCell   *lc;

	free_expr(stmt->query);
	free_expr(stmt->dynquery);
	foreach(lc, stmt->params)
	{
		free_expr((PLMySQL_expr *) lfirst(lc));
	}
}

static void
free_raise(PLMySQL_stmt_raise *stmt)
{
	ListCell   *lc;

	foreach(lc, stmt->params)
	{
		free_expr((PLMySQL_expr *) lfirst(lc));
	}
	foreach(lc, stmt->options)
	{
		PLMySQL_raise_option *opt = (PLMySQL_raise_option *) lfirst(lc);

		free_expr(opt->expr);
	}
}

static void
free_assert(PLMySQL_stmt_assert *stmt)
{
	free_expr(stmt->cond);
	free_expr(stmt->message);
}

static void
free_execsql(PLMySQL_stmt_execsql *stmt)
{
	free_expr(stmt->sqlstmt);
}

static void
free_dynexecute(PLMySQL_stmt_dynexecute *stmt)
{
	ListCell   *lc;

	free_expr(stmt->query);
	foreach(lc, stmt->params)
	{
		free_expr((PLMySQL_expr *) lfirst(lc));
	}
}

static void
free_getdiag(PLMySQL_stmt_getdiag *stmt)
{
}

static void
free_expr(PLMySQL_expr *expr)
{
	if (expr && expr->plan)
	{
		SPI_freeplan(expr->plan);
		expr->plan = NULL;
	}
}

void
plmysql_free_function_memory(PLMySQL_function *func)
{
	int			i;

	/* Better not call this on an in-use function */
	Assert(func->use_count == 0);

	/* Release plans associated with variable declarations */
	for (i = 0; i < func->ndatums; i++)
	{
		PLMySQL_datum *d = func->datums[i];

		switch (d->dtype)
		{
			case PLMYSQL_DTYPE_VAR:
			case PLMYSQL_DTYPE_PROMISE:
				{
					PLMySQL_var *var = (PLMySQL_var *) d;

					free_expr(var->default_val);
					free_expr(var->cursor_explicit_expr);
				}
				break;
			case PLMYSQL_DTYPE_ROW:
				break;
			case PLMYSQL_DTYPE_REC:
				{
					PLMySQL_rec *rec = (PLMySQL_rec *) d;

					free_expr(rec->default_val);
				}
				break;
			case PLMYSQL_DTYPE_RECFIELD:
				break;
			default:
				elog(ERROR, "unrecognized data type: %d", d->dtype);
		}
	}
	func->ndatums = 0;

	/* Release plans in statement tree */
	if (func->action)
		free_block(func->action);
	func->action = NULL;

	/*
	 * And finally, release all memory except the PLMySQL_function struct
	 * itself (which has to be kept around because there may be multiple
	 * fn_extra pointers to it).
	 */
	if (func->fn_cxt)
		MemoryContextDelete(func->fn_cxt);
	func->fn_cxt = NULL;
}


/**********************************************************************
 * Debug functions for analyzing the compiled code
 **********************************************************************/
static int	dump_indent;

static void dump_ind(void);
static void dump_stmt(PLMySQL_stmt *stmt);
static void dump_block(PLMySQL_stmt_block *block);
static void dump_assign(PLMySQL_stmt_assign *stmt);
static void dump_if(PLMySQL_stmt_if *stmt);
static void dump_case(PLMySQL_stmt_case *stmt);
static void dump_loop(PLMySQL_stmt_loop *stmt);
static void dump_while(PLMySQL_stmt_while *stmt);
static void dump_exit(PLMySQL_stmt_exit *stmt);
static void dump_return(PLMySQL_stmt_return *stmt);
static void dump_return_next(PLMySQL_stmt_return_next *stmt);
static void dump_return_query(PLMySQL_stmt_return_query *stmt);
static void dump_raise(PLMySQL_stmt_raise *stmt);
static void dump_signal(PLMySQL_stmt_signal *stmt);
static void dump_assert(PLMySQL_stmt_assert *stmt);
static void dump_execsql(PLMySQL_stmt_execsql *stmt);
static void dump_dynexecute(PLMySQL_stmt_dynexecute *stmt);
static void dump_getdiag(PLMySQL_stmt_getdiag *stmt);
static void dump_open(PLMySQL_stmt_open *stmt);
static void dump_fetch(PLMySQL_stmt_fetch *stmt);
static void dump_cursor_direction(PLMySQL_stmt_fetch *stmt);
static void dump_close(PLMySQL_stmt_close *stmt);
static void dump_perform(PLMySQL_stmt_perform *stmt);
static void dump_call(PLMySQL_stmt_call *stmt);
static void dump_commit(PLMySQL_stmt_commit *stmt);
static void dump_rollback(PLMySQL_stmt_rollback *stmt);
static void dump_savepoint(PLMySQL_stmt_savepoint *stmt);
static void dump_expr(PLMySQL_expr *expr);


static void
dump_ind(void)
{
	int			i;

	for (i = 0; i < dump_indent; i++)
		printf(" ");
}

static void
dump_stmt(PLMySQL_stmt *stmt)
{
	printf("%3d:", stmt->lineno);
	switch (stmt->cmd_type)
	{
		case PLMYSQL_STMT_BLOCK:
			dump_block((PLMySQL_stmt_block *) stmt);
			break;
		case PLMYSQL_STMT_ASSIGN:
			dump_assign((PLMySQL_stmt_assign *) stmt);
			break;
		case PLMYSQL_STMT_IF:
			dump_if((PLMySQL_stmt_if *) stmt);
			break;
		case PLMYSQL_STMT_CASE:
			dump_case((PLMySQL_stmt_case *) stmt);
			break;
		case PLMYSQL_STMT_LOOP:
			dump_loop((PLMySQL_stmt_loop *) stmt);
			break;
		case PLMYSQL_STMT_WHILE:
			dump_while((PLMySQL_stmt_while *) stmt);
			break;
		case PLMYSQL_STMT_EXIT:
			dump_exit((PLMySQL_stmt_exit *) stmt);
			break;
		case PLMYSQL_STMT_RETURN:
			dump_return((PLMySQL_stmt_return *) stmt);
			break;
		case PLMYSQL_STMT_RETURN_NEXT:
			dump_return_next((PLMySQL_stmt_return_next *) stmt);
			break;
		case PLMYSQL_STMT_RETURN_QUERY:
			dump_return_query((PLMySQL_stmt_return_query *) stmt);
			break;
		case PLMYSQL_STMT_RAISE:
			dump_raise((PLMySQL_stmt_raise *) stmt);
			break;
		case PLMYSQL_STMT_SIGNAL:
			dump_signal((PLMySQL_stmt_signal *) stmt);
			break;
		case PLMYSQL_STMT_ASSERT:
			dump_assert((PLMySQL_stmt_assert *) stmt);
			break;
		case PLMYSQL_STMT_EXECSQL:
			dump_execsql((PLMySQL_stmt_execsql *) stmt);
			break;
		case PLMYSQL_STMT_DYNEXECUTE:
			dump_dynexecute((PLMySQL_stmt_dynexecute *) stmt);
			break;
		case PLMYSQL_STMT_GETDIAG:
			dump_getdiag((PLMySQL_stmt_getdiag *) stmt);
			break;
		case PLMYSQL_STMT_OPEN:
			dump_open((PLMySQL_stmt_open *) stmt);
			break;
		case PLMYSQL_STMT_FETCH:
			dump_fetch((PLMySQL_stmt_fetch *) stmt);
			break;
		case PLMYSQL_STMT_CLOSE:
			dump_close((PLMySQL_stmt_close *) stmt);
			break;
		case PLMYSQL_STMT_PERFORM:
			dump_perform((PLMySQL_stmt_perform *) stmt);
			break;
		case PLMYSQL_STMT_CALL:
			dump_call((PLMySQL_stmt_call *) stmt);
			break;
		case PLMYSQL_STMT_COMMIT:
			dump_commit((PLMySQL_stmt_commit *) stmt);
			break;
		case PLMYSQL_STMT_ROLLBACK:
			dump_rollback((PLMySQL_stmt_rollback *) stmt);
			break;
		case PLMYSQL_STMT_START:
		case PLMYSQL_STMT_SAVEPOINT:
		case PLMYSQL_STMT_ROLLBACK_TO:
		case PLMYSQL_STMT_RELEASE_SAVEPOINT:
			dump_savepoint((PLMySQL_stmt_savepoint *) stmt);
			break;
		default:
			elog(ERROR, "unrecognized cmd_type: %d", stmt->cmd_type);
			break;
	}
}

static void
dump_stmts(List *stmts)
{
	ListCell   *s;

	dump_indent += 2;
	foreach(s, stmts)
		dump_stmt((PLMySQL_stmt *) lfirst(s));
	dump_indent -= 2;
}

static void
dump_block(PLMySQL_stmt_block *block)
{
	char	   *name;

	if (block->label == NULL)
		name = "*unnamed*";
	else
		name = block->label;

	dump_ind();
	printf("BLOCK <<%s>>\n", name);

	dump_stmts(block->body);

	if (block->exceptions)
	{
		ListCell   *e;

		foreach(e, block->exceptions->exc_list)
		{
			PLMySQL_exception *exc = (PLMySQL_exception *) lfirst(e);
			PLMySQL_condition *cond;

			dump_ind();
			printf("    EXCEPTION WHEN ");
			for (cond = exc->conditions; cond; cond = cond->next)
			{
				if (cond != exc->conditions)
					printf(" OR ");
				printf("%s", cond->condname);
			}
			printf(" THEN\n");
			dump_stmts(exc->action);
		}
	}

	dump_ind();
	printf("    END -- %s\n", name);
}

static void
dump_assign(PLMySQL_stmt_assign *stmt)
{
	dump_ind();
	printf("ASSIGN var %d := ", stmt->varno);
	dump_expr(stmt->expr);
	printf("\n");
}

static void
dump_if(PLMySQL_stmt_if *stmt)
{
	ListCell   *l;

	dump_ind();
	printf("IF ");
	dump_expr(stmt->cond);
	printf(" THEN\n");
	dump_stmts(stmt->then_body);
	foreach(l, stmt->elsif_list)
	{
		PLMySQL_if_elsif *elif = (PLMySQL_if_elsif *) lfirst(l);

		dump_ind();
		printf("    ELSIF ");
		dump_expr(elif->cond);
		printf(" THEN\n");
		dump_stmts(elif->stmts);
	}
	if (stmt->else_body != NIL)
	{
		dump_ind();
		printf("    ELSE\n");
		dump_stmts(stmt->else_body);
	}
	dump_ind();
	printf("    ENDIF\n");
}

static void
dump_case(PLMySQL_stmt_case *stmt)
{
	ListCell   *l;

	dump_ind();
	printf("CASE %d ", stmt->t_varno);
	if (stmt->t_expr)
		dump_expr(stmt->t_expr);
	printf("\n");
	dump_indent += 6;
	foreach(l, stmt->case_when_list)
	{
		PLMySQL_case_when *cwt = (PLMySQL_case_when *) lfirst(l);

		dump_ind();
		printf("WHEN ");
		dump_expr(cwt->expr);
		printf("\n");
		dump_ind();
		printf("THEN\n");
		dump_indent += 2;
		dump_stmts(cwt->stmts);
		dump_indent -= 2;
	}
	if (stmt->have_else)
	{
		dump_ind();
		printf("ELSE\n");
		dump_indent += 2;
		dump_stmts(stmt->else_stmts);
		dump_indent -= 2;
	}
	dump_indent -= 6;
	dump_ind();
	printf("    ENDCASE\n");
}

static void
dump_loop(PLMySQL_stmt_loop *stmt)
{
	dump_ind();
	printf("LOOP\n");

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDLOOP\n");
}

static void
dump_while(PLMySQL_stmt_while *stmt)
{
	dump_ind();
	printf("WHILE ");
	dump_expr(stmt->cond);
	printf("\n");

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDWHILE\n");
}

static void
dump_open(PLMySQL_stmt_open *stmt)
{
	dump_ind();
	printf("OPEN curvar=%d\n", stmt->curvar);

	dump_indent += 2;
	if (stmt->argquery != NULL)
	{
		dump_ind();
		printf("  arguments = '");
		dump_expr(stmt->argquery);
		printf("'\n");
	}
	if (stmt->query != NULL)
	{
		dump_ind();
		printf("  query = '");
		dump_expr(stmt->query);
		printf("'\n");
	}
	if (stmt->dynquery != NULL)
	{
		dump_ind();
		printf("  execute = '");
		dump_expr(stmt->dynquery);
		printf("'\n");

		if (stmt->params != NIL)
		{
			ListCell   *lc;
			int			i;

			dump_indent += 2;
			dump_ind();
			printf("    USING\n");
			dump_indent += 2;
			i = 1;
			foreach(lc, stmt->params)
			{
				dump_ind();
				printf("    parameter $%d: ", i++);
				dump_expr((PLMySQL_expr *) lfirst(lc));
				printf("\n");
			}
			dump_indent -= 4;
		}
	}
	dump_indent -= 2;
}

static void
dump_fetch(PLMySQL_stmt_fetch *stmt)
{
	dump_ind();

	if (!stmt->is_move)
	{
		printf("FETCH curvar=%d\n", stmt->curvar);
		dump_cursor_direction(stmt);

		dump_indent += 2;
		if (stmt->target != NULL)
		{
			dump_ind();
			printf("    target = %d %s\n",
				   stmt->target->dno, stmt->target->refname);
		}
		dump_indent -= 2;
	}
	else
	{
		printf("MOVE curvar=%d\n", stmt->curvar);
		dump_cursor_direction(stmt);
	}
}

static void
dump_cursor_direction(PLMySQL_stmt_fetch *stmt)
{
	dump_indent += 2;
	dump_ind();
	switch (stmt->direction)
	{
		case FETCH_FORWARD:
			printf("    FORWARD ");
			break;
		case FETCH_BACKWARD:
			printf("    BACKWARD ");
			break;
		case FETCH_ABSOLUTE:
			printf("    ABSOLUTE ");
			break;
		case FETCH_RELATIVE:
			printf("    RELATIVE ");
			break;
		default:
			printf("??? unknown cursor direction %d", stmt->direction);
	}

	if (stmt->expr)
	{
		dump_expr(stmt->expr);
		printf("\n");
	}
	else
		printf("%ld\n", stmt->how_many);

	dump_indent -= 2;
}

static void
dump_close(PLMySQL_stmt_close *stmt)
{
	dump_ind();
	printf("CLOSE curvar=%d\n", stmt->curvar);
}

static void
dump_perform(PLMySQL_stmt_perform *stmt)
{
	dump_ind();
	printf("PERFORM expr = ");
	dump_expr(stmt->expr);
	printf("\n");
}

static void
dump_call(PLMySQL_stmt_call *stmt)
{
	dump_ind();
	printf("%s expr = ", stmt->is_call ? "CALL" : "DO");
	dump_expr(stmt->expr);
	printf("\n");
}

static void
dump_commit(PLMySQL_stmt_commit *stmt)
{
	dump_ind();
	if (stmt->chain)
		printf("COMMIT AND CHAIN\n");
	else
		printf("COMMIT\n");
}

static void
dump_rollback(PLMySQL_stmt_rollback *stmt)
{
	dump_ind();
	if (stmt->chain)
		printf("ROLLBACK AND CHAIN\n");
	else
		printf("ROLLBACK\n");
}

static void
dump_savepoint(PLMySQL_stmt_savepoint *stmt)
{
	dump_ind();
	switch (stmt->cmd_type)
	{
		case PLMYSQL_STMT_START:
			printf("START TRANSACTION\n");
			break;
		case PLMYSQL_STMT_SAVEPOINT:
			printf("SAVEPOINT %s\n", stmt->name);
			break;
		case PLMYSQL_STMT_ROLLBACK_TO:
			printf("ROLLBACK TO SAVEPOINT %s\n", stmt->name);
			break;
		case PLMYSQL_STMT_RELEASE_SAVEPOINT:
			printf("RELEASE SAVEPOINT %s\n", stmt->name);
			break;
		default:
			break;
	}
}

static void
dump_exit(PLMySQL_stmt_exit *stmt)
{
	dump_ind();
	printf("%s", stmt->is_exit ? "EXIT" : "CONTINUE");
	if (stmt->label != NULL)
		printf(" label='%s'", stmt->label);
	if (stmt->cond != NULL)
	{
		printf(" WHEN ");
		dump_expr(stmt->cond);
	}
	printf("\n");
}

static void
dump_return(PLMySQL_stmt_return *stmt)
{
	dump_ind();
	printf("RETURN ");
	if (stmt->retvarno >= 0)
		printf("variable %d", stmt->retvarno);
	else if (stmt->expr != NULL)
		dump_expr(stmt->expr);
	else
		printf("NULL");
	printf("\n");
}

static void
dump_return_next(PLMySQL_stmt_return_next *stmt)
{
	dump_ind();
	printf("RETURN NEXT ");
	if (stmt->retvarno >= 0)
		printf("variable %d", stmt->retvarno);
	else if (stmt->expr != NULL)
		dump_expr(stmt->expr);
	else
		printf("NULL");
	printf("\n");
}

static void
dump_return_query(PLMySQL_stmt_return_query *stmt)
{
	dump_ind();
	if (stmt->query)
	{
		printf("RETURN QUERY ");
		dump_expr(stmt->query);
		printf("\n");
	}
	else
	{
		printf("RETURN QUERY EXECUTE ");
		dump_expr(stmt->dynquery);
		printf("\n");
		if (stmt->params != NIL)
		{
			ListCell   *lc;
			int			i;

			dump_indent += 2;
			dump_ind();
			printf("    USING\n");
			dump_indent += 2;
			i = 1;
			foreach(lc, stmt->params)
			{
				dump_ind();
				printf("    parameter $%d: ", i++);
				dump_expr((PLMySQL_expr *) lfirst(lc));
				printf("\n");
			}
			dump_indent -= 4;
		}
	}
}

static void
dump_raise(PLMySQL_stmt_raise *stmt)
{
	ListCell   *lc;
	int			i = 0;

	dump_ind();
	printf("RAISE level=%d", stmt->elog_level);
	if (stmt->condname)
		printf(" condname='%s'", stmt->condname);
	if (stmt->message)
		printf(" message='%s'", stmt->message);
	printf("\n");
	dump_indent += 2;
	foreach(lc, stmt->params)
	{
		dump_ind();
		printf("    parameter %d: ", i++);
		dump_expr((PLMySQL_expr *) lfirst(lc));
		printf("\n");
	}
	if (stmt->options)
	{
		dump_ind();
		printf("    USING\n");
		dump_indent += 2;
		foreach(lc, stmt->options)
		{
			PLMySQL_raise_option *opt = (PLMySQL_raise_option *) lfirst(lc);

			dump_ind();
			switch (opt->opt_type)
			{
				case PLMYSQL_RAISEOPTION_ERRCODE:
					printf("    ERRCODE = ");
					break;
				case PLMYSQL_RAISEOPTION_MESSAGE:
					printf("    MESSAGE = ");
					break;
				case PLMYSQL_RAISEOPTION_DETAIL:
					printf("    DETAIL = ");
					break;
				case PLMYSQL_RAISEOPTION_HINT:
					printf("    HINT = ");
					break;
				case PLMYSQL_RAISEOPTION_COLUMN:
					printf("    COLUMN = ");
					break;
				case PLMYSQL_RAISEOPTION_CONSTRAINT:
					printf("    CONSTRAINT = ");
					break;
				case PLMYSQL_RAISEOPTION_DATATYPE:
					printf("    DATATYPE = ");
					break;
				case PLMYSQL_RAISEOPTION_TABLE:
					printf("    TABLE = ");
					break;
				case PLMYSQL_RAISEOPTION_SCHEMA:
					printf("    SCHEMA = ");
					break;
			}
			dump_expr(opt->expr);
			printf("\n");
		}
		dump_indent -= 2;
	}
	dump_indent -= 2;
}

static void
dump_signal(PLMySQL_stmt_signal *stmt)
{
	dump_ind();
	printf("%s: sqlstate=%s\n", stmt->is_resignal ? "RESIGNAL" : "SIGNAL",
		   stmt->sqlstate ? stmt->sqlstate : "(none)");
}


static void
dump_assert(PLMySQL_stmt_assert *stmt)
{
	dump_ind();
	printf("ASSERT ");
	dump_expr(stmt->cond);
	printf("\n");

	dump_indent += 2;
	if (stmt->message != NULL)
	{
		dump_ind();
		printf("    MESSAGE = ");
		dump_expr(stmt->message);
		printf("\n");
	}
	dump_indent -= 2;
}

static void
dump_execsql(PLMySQL_stmt_execsql *stmt)
{
	dump_ind();
	printf("EXECSQL ");
	dump_expr(stmt->sqlstmt);
	printf("\n");

	dump_indent += 2;
	if (stmt->target != NULL)
	{
		dump_ind();
		printf("    INTO%s target = %d %s\n",
			   stmt->strict ? " STRICT" : "",
			   stmt->target->dno, stmt->target->refname);
	}
	dump_indent -= 2;
}

static void
dump_dynexecute(PLMySQL_stmt_dynexecute *stmt)
{
	dump_ind();
	printf("EXECUTE ");
	dump_expr(stmt->query);
	printf("\n");

	dump_indent += 2;
	if (stmt->target != NULL)
	{
		dump_ind();
		printf("    INTO%s target = %d %s\n",
			   stmt->strict ? " STRICT" : "",
			   stmt->target->dno, stmt->target->refname);
	}
	if (stmt->params != NIL)
	{
		ListCell   *lc;
		int			i;

		dump_ind();
		printf("    USING\n");
		dump_indent += 2;
		i = 1;
		foreach(lc, stmt->params)
		{
			dump_ind();
			printf("    parameter %d: ", i++);
			dump_expr((PLMySQL_expr *) lfirst(lc));
			printf("\n");
		}
		dump_indent -= 2;
	}
	dump_indent -= 2;
}

static void
dump_getdiag(PLMySQL_stmt_getdiag *stmt)
{
	ListCell   *lc;

	dump_ind();
	printf("GET %s DIAGNOSTICS ", stmt->is_stacked ? "STACKED" : "CURRENT");
	foreach(lc, stmt->diag_items)
	{
		PLMySQL_diag_item *diag_item = (PLMySQL_diag_item *) lfirst(lc);

		if (lc != list_head(stmt->diag_items))
			printf(", ");

		printf("{var %d} = %s", diag_item->target,
			   plmysql_getdiag_kindname(diag_item->kind));
	}
	printf("\n");
}

static void
dump_expr(PLMySQL_expr *expr)
{
	printf("'%s'", expr->query);
}

void
plmysql_dumptree(PLMySQL_function *func)
{
	int			i;
	PLMySQL_datum *d;

	printf("\nExecution tree of successfully compiled PL/MySQL function %s:\n",
		   func->fn_signature);

	printf("\nFunction's data area:\n");
	for (i = 0; i < func->ndatums; i++)
	{
		d = func->datums[i];

		printf("    entry %d: ", i);
		switch (d->dtype)
		{
			case PLMYSQL_DTYPE_VAR:
			case PLMYSQL_DTYPE_PROMISE:
				{
					PLMySQL_var *var = (PLMySQL_var *) d;

					printf("VAR %-16s type %s (typoid %u) atttypmod %d\n",
						   var->refname, var->datatype->typname,
						   var->datatype->typoid,
						   var->datatype->atttypmod);
					if (var->isconst)
						printf("                                  CONSTANT\n");
					if (var->notnull)
						printf("                                  NOT NULL\n");
					if (var->default_val != NULL)
					{
						printf("                                  DEFAULT ");
						dump_expr(var->default_val);
						printf("\n");
					}
					if (var->cursor_explicit_expr != NULL)
					{
						if (var->cursor_explicit_argrow >= 0)
							printf("                                  CURSOR argument row %d\n", var->cursor_explicit_argrow);

						printf("                                  CURSOR IS ");
						dump_expr(var->cursor_explicit_expr);
						printf("\n");
					}
					if (var->promise != PLMYSQL_PROMISE_NONE)
						printf("                                  PROMISE %d\n",
							   (int) var->promise);
				}
				break;
			case PLMYSQL_DTYPE_ROW:
				{
					PLMySQL_row *row = (PLMySQL_row *) d;
					int			i;

					printf("ROW %-16s fields", row->refname);
					for (i = 0; i < row->nfields; i++)
					{
						printf(" %s=var %d", row->fieldnames[i],
							   row->varnos[i]);
					}
					printf("\n");
				}
				break;
			case PLMYSQL_DTYPE_REC:
				printf("REC %-16s typoid %u\n",
					   ((PLMySQL_rec *) d)->refname,
					   ((PLMySQL_rec *) d)->rectypeid);
				if (((PLMySQL_rec *) d)->isconst)
					printf("                                  CONSTANT\n");
				if (((PLMySQL_rec *) d)->notnull)
					printf("                                  NOT NULL\n");
				if (((PLMySQL_rec *) d)->default_val != NULL)
				{
					printf("                                  DEFAULT ");
					dump_expr(((PLMySQL_rec *) d)->default_val);
					printf("\n");
				}
				break;
			case PLMYSQL_DTYPE_RECFIELD:
				printf("RECFIELD %-16s of REC %d\n",
					   ((PLMySQL_recfield *) d)->fieldname,
					   ((PLMySQL_recfield *) d)->recparentno);
				break;
			default:
				printf("??? unknown data type %d\n", d->dtype);
		}
	}
	printf("\nFunction's statements:\n");

	dump_indent = 0;
	printf("%3d:", func->action->lineno);
	dump_block(func->action);
	printf("\nEnd of execution tree of function %s\n\n", func->fn_signature);
	fflush(stdout);
}

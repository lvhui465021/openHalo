/*-------------------------------------------------------------------------
 *
 * pl_handler.c		- Handler for the PL/MySQL
 *			  procedural language
 *
 * Portions Copyright (c) 2026, Halo Tech Co.,Ltd.
 * Portions Copyright (c) 1996-2021, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/pl/plmysql/src/pl_handler.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/htup_details.h"
#include "adapter/mysql/errorConvertor.h"
#include "adapter/mysql/systemVar.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "commands/seclabel.h"
#include "funcapi.h"
#include "libpq/libpq-be.h"
#include "miscadmin.h"
#include "nodes/nodes.h"
#include "plmysql.h"
#include "storage/ipc.h"
#include "adapter/mysql/adapter.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "utils/varlena.h"

static bool plmysql_extra_checks_check_hook(char **newvalue, void **extra, GucSource source);
static void plmysql_extra_warnings_assign_hook(const char *newvalue, void *extra);
static void plmysql_extra_errors_assign_hook(const char *newvalue, void *extra);
static void plmysql_require_mysql_protocol(void);

typedef struct PLMySQL_sql_mode_scope
{
	uint64		saved_mode;
	bool		saved_strict;
	bool		active;
} PLMySQL_sql_mode_scope;

static void plmysql_restore_sql_mode(PLMySQL_sql_mode_scope *scope);
static void plmysql_sql_mode_error_cleanup(int code, Datum arg);
static bool plmysql_get_sql_mode_snapshot(Oid fn_oid, char **sql_mode_out);
static void plmysql_seclabel_check(const ObjectAddress *object, const char *seclabel);

/*
 * This is deliberately a backend-local stack.  A PL handler invocation
 * cannot cross a backend boundary, and the entries themselves live in their
 * invoking handler frames, so PG_TRY/PG_FINALLY can reliably unwind it.
 */
typedef struct PLMySQL_call_stack_entry
{
	Oid			fn_oid;
	struct PLMySQL_call_stack_entry *prev;
} PLMySQL_call_stack_entry;

static PLMySQL_call_stack_entry *plmysql_call_stack = NULL;

static void plmysql_check_recursion(PLMySQL_function *func);

PG_MODULE_MAGIC;

/* Custom GUC variable */
static const struct config_enum_entry variable_conflict_options[] = {
	{"error", PLMYSQL_RESOLVE_ERROR, false},
	{"use_variable", PLMYSQL_RESOLVE_VARIABLE, false},
	{"use_column", PLMYSQL_RESOLVE_COLUMN, false},
	{NULL, 0, false}
};

/*
 * MySQL resolves an unqualified name in an embedded SQL statement as a table
 * column first, and only falls back to a routine-local variable or parameter
 * when no such column exists.  That is exactly the use_column behavior, so
 * unlike plpgsql (whose default raises an ambiguity error) the plmysql
 * default follows MySQL.
 */
int			plmysql_variable_conflict = PLMYSQL_RESOLVE_COLUMN;

bool		plmysql_print_strict_params = false;

bool		plmysql_check_asserts = true;

char	   *plmysql_extra_warnings_string = NULL;
char	   *plmysql_extra_errors_string = NULL;
int			plmysql_extra_warnings;
int			plmysql_extra_errors;

/* Trigger metadata carried in pg_proc.proconfig (see _PG_init). */
char	   *plmysql_definer_string = NULL;
char	   *plmysql_trigger_body_string = NULL;
char	   *plmysql_trigger_name_string = NULL;

/* Hook for plugins */
PLMySQL_plugin **plmysql_plugin_ptr = NULL;


static bool
plmysql_extra_checks_check_hook(char **newvalue, void **extra, GucSource source)
{
	char	   *rawstring;
	List	   *elemlist;
	ListCell   *l;
	int			extrachecks = 0;
	int		   *myextra;

	if (pg_strcasecmp(*newvalue, "all") == 0)
		extrachecks = PLMYSQL_XCHECK_ALL;
	else if (pg_strcasecmp(*newvalue, "none") == 0)
		extrachecks = PLMYSQL_XCHECK_NONE;
	else
	{
		/* Need a modifiable copy of string */
		rawstring = pstrdup(*newvalue);

		/* Parse string into list of identifiers */
		if (!SplitIdentifierString(rawstring, ',', &elemlist))
		{
			/* syntax error in list */
			GUC_check_errdetail("List syntax is invalid.");
			pfree(rawstring);
			list_free(elemlist);
			return false;
		}

		foreach(l, elemlist)
		{
			char	   *tok = (char *) lfirst(l);

			if (pg_strcasecmp(tok, "shadowed_variables") == 0)
				extrachecks |= PLMYSQL_XCHECK_SHADOWVAR;
			else if (pg_strcasecmp(tok, "too_many_rows") == 0)
				extrachecks |= PLMYSQL_XCHECK_TOOMANYROWS;
			else if (pg_strcasecmp(tok, "strict_multi_assignment") == 0)
				extrachecks |= PLMYSQL_XCHECK_STRICTMULTIASSIGNMENT;
			else if (pg_strcasecmp(tok, "all") == 0 || pg_strcasecmp(tok, "none") == 0)
			{
				GUC_check_errdetail("Key word \"%s\" cannot be combined with other key words.", tok);
				pfree(rawstring);
				list_free(elemlist);
				return false;
			}
			else
			{
				GUC_check_errdetail("Unrecognized key word: \"%s\".", tok);
				pfree(rawstring);
				list_free(elemlist);
				return false;
			}
		}

		pfree(rawstring);
		list_free(elemlist);
	}

	myextra = (int *) malloc(sizeof(int));
	if (!myextra)
		return false;
	*myextra = extrachecks;
	*extra = (void *) myextra;

	return true;
}

static void
plmysql_extra_warnings_assign_hook(const char *newvalue, void *extra)
{
	plmysql_extra_warnings = *((int *) extra);
}

static void
plmysql_extra_errors_assign_hook(const char *newvalue, void *extra)
{
	plmysql_extra_errors = *((int *) extra);
}

/*
 * pg_proc.proconfig activates plmysql.sql_mode before the handler runs, but
 * the MySQL adapter's coercion/date code reads its own backend-local flags.
 * Bridge the two states for one routine invocation and always put the caller
 * state back, including a nested CALL or an ERROR unwinding through us.
 */
static void
plmysql_restore_sql_mode(PLMySQL_sql_mode_scope *scope)
{
	if (!scope->active)
		return;

	mys_sqlMode = scope->saved_mode;
	isStrictTransTablesOn = scope->saved_strict;
	scope->active = false;
}

static void
plmysql_sql_mode_error_cleanup(int code, Datum arg)
{
	(void) code;
	plmysql_restore_sql_mode((PLMySQL_sql_mode_scope *) DatumGetPointer(arg));
}

/*
 * check_object_relabel_type hook for the "plmysql" security-label provider
 * (registered in _PG_init()).  Accepts any label unconditionally: the only
 * writer is plmysql itself (mys_plmysql_set_meta_label(), mys_utility.c),
 * calling SetSecurityLabel() directly rather than through the SQL statement
 * this hook guards, so this only ever runs for pg_restore replaying a
 * previously dumped SECURITY LABEL FOR plmysql ON FUNCTION/PROCEDURE ...
 * statement -- content this same process generated on the dump side.
 */
static void
plmysql_seclabel_check(const ObjectAddress *object, const char *seclabel)
{
	(void) object;
	(void) seclabel;
}

/*
 * An empty sql_mode is a real MySQL snapshot, not the absence of one, so the
 * caller needs a real found/not-found signal rather than just an empty
 * string.  The snapshot itself now lives in the routine's "plmysql" security
 * label rather than pg_proc.proconfig (see mys_plmysql_meta_marker() in
 * mys_utility.c for why: proconfig forces PostgreSQL's ExecuteCallStmt() to
 * treat any CALL of the routine as atomic, blocking COMMIT/ROLLBACK in its
 * body -- the C2 gap in the compat report). Returns false, leaving
 * *sql_mode_out untouched, for a routine with no plmysql.sql_mode entry in
 * its label (predates this mechanism, or was never a plmysql routine).
 */
static bool
plmysql_get_sql_mode_snapshot(Oid fn_oid, char **sql_mode_out)
{
	static const char setting[] = "plmysql.sql_mode=";
	const size_t setting_len = sizeof(setting) - 1;
	ObjectAddress address;
	char	   *label;
	char	   *cursor;

	ObjectAddressSet(address, ProcedureRelationId, fn_oid);
	label = GetSecurityLabel(&address, "plmysql");
	if (label == NULL)
		return false;

	for (cursor = label; cursor != NULL && *cursor != '\0'; )
	{
		char	   *nl = strchr(cursor, '\n');
		size_t		linelen = nl ? (size_t) (nl - cursor) : strlen(cursor);

		if (linelen >= setting_len &&
			strncmp(cursor, setting, setting_len) == 0)
		{
			*sql_mode_out = pnstrdup(cursor + setting_len, linelen - setting_len);
			return true;
		}
		cursor = nl ? nl + 1 : NULL;
	}
	return false;
}


/*
 * _PG_init()			- library load-time initialization
 *
 * DO NOT make this static nor change its name!
 */
void
_PG_init(void)
{
	/* Be sure we do initialization only once (should be redundant now) */
	static bool inited = false;

	if (inited)
		return;

	pg_bindtextdomain(TEXTDOMAIN);

	DefineCustomEnumVariable("plmysql.variable_conflict",
							 gettext_noop("Sets handling of conflicts between PL/MySQL variable names and table column names."),
							 NULL,
							 &plmysql_variable_conflict,
							 PLMYSQL_RESOLVE_COLUMN,
							 variable_conflict_options,
							 PGC_SUSET, 0,
							 NULL, NULL, NULL);

	DefineCustomBoolVariable("plmysql.print_strict_params",
							 gettext_noop("Print information about parameters in the DETAIL part of the error messages generated on INTO ... STRICT failures."),
							 NULL,
							 &plmysql_print_strict_params,
							 false,
							 PGC_USERSET, 0,
							 NULL, NULL, NULL);

	DefineCustomBoolVariable("plmysql.check_asserts",
							 gettext_noop("Perform checks given in ASSERT statements."),
							 NULL,
							 &plmysql_check_asserts,
							 true,
							 PGC_USERSET, 0,
							 NULL, NULL, NULL);

	DefineCustomStringVariable("plmysql.extra_warnings",
							   gettext_noop("List of programming constructs that should produce a warning."),
							   NULL,
							   &plmysql_extra_warnings_string,
							   "none",
							   PGC_USERSET, GUC_LIST_INPUT,
							   plmysql_extra_checks_check_hook,
							   plmysql_extra_warnings_assign_hook,
							   NULL);

	DefineCustomStringVariable("plmysql.extra_errors",
							   gettext_noop("List of programming constructs that should produce an error."),
							   NULL,
							   &plmysql_extra_errors_string,
							   "none",
							   PGC_USERSET, GUC_LIST_INPUT,
							   plmysql_extra_checks_check_hook,
							   plmysql_extra_errors_assign_hook,
							   NULL);

	/*
	 * Trigger metadata that pg_proc cannot carry, stored as function-local
	 * GUC settings (proconfig) on a MySQL trigger's private underlying
	 * function (mys_make_mysql_trigger_function(), mys_utility.c).  Writing
	 * them through proconfig rather than a companion catalog keeps them
	 * attached to the routine across pg_dump/pg_restore and logical
	 * replication.  A regular (non-trigger) CREATE/ALTER FUNCTION or
	 * PROCEDURE's own equivalent metadata -- definer, sql_mode snapshot,
	 * created, last_altered, sql_data_access -- deliberately does NOT use
	 * proconfig any more (see mys_plmysql_meta_marker() in mys_utility.c):
	 * proconfig forces PostgreSQL's ExecuteCallStmt() to treat any CALL of
	 * the routine as atomic, blocking COMMIT/ROLLBACK in its body, so those
	 * items are carried as a "plmysql" security label instead, read back via
	 * GetSecurityLabel() (see plmysql_get_sql_mode_snapshot() below) or, for
	 * the display-only ones, by aux_mysql's mysql.get_plmysql_config() SQL
	 * function.  A trigger is never dispatched through CALL's atomic/non-
	 * atomic machinery, so proconfig's side effect doesn't apply to it, and
	 * plmysql.definer is needed as a real GUC here regardless since a
	 * trigger's private function still records it through this same
	 * proconfig mechanism.
	 */
	DefineCustomStringVariable("plmysql.definer",
							   gettext_noop("Definer account recorded at routine creation, as user@host."),
							   NULL,
							   &plmysql_definer_string,
							   "",
							   PGC_USERSET, 0,
							   NULL, NULL, NULL);
	DefineCustomStringVariable("plmysql.trigger_body",
							   gettext_noop("Original MySQL trigger body stored for metadata display."),
							   NULL,
							   &plmysql_trigger_body_string,
							   "",
							   PGC_USERSET, 0,
							   NULL, NULL, NULL);
	DefineCustomStringVariable("plmysql.trigger_name",
							   gettext_noop("Original MySQL trigger name stored for metadata display."),
							   NULL,
							   &plmysql_trigger_name_string,
							   "",
							   PGC_USERSET, 0,
							   NULL, NULL, NULL);

	EmitWarningsOnPlaceholders("plmysql");

	/*
	 * Register the "plmysql" security-label provider so that a dumped
	 * SECURITY LABEL FOR plmysql ON FUNCTION/PROCEDURE ... statement (see
	 * mys_plmysql_set_meta_label(), mys_utility.c) can be replayed by
	 * pg_restore: PostgreSQL's SECURITY LABEL statement path refuses to
	 * write a label for an unregistered provider.  plmysql itself only ever
	 * writes these labels directly via SetSecurityLabel(), which does not
	 * go through this check, so the hook just needs to exist, not validate
	 * anything -- there is no untrusted input to police here.
	 */
	register_label_provider("plmysql", plmysql_seclabel_check);

	plmysql_HashTableInit();
	RegisterXactCallback(plmysql_xact_cb, NULL);
	RegisterSubXactCallback(plmysql_subxact_cb, NULL);

	/* Set up a rendezvous point with optional instrumentation plugin */
	plmysql_plugin_ptr = (PLMySQL_plugin **) find_rendezvous_variable("PLMySQL_plugin");

	inited = true;
}

/*
 * plmysql_require_mysql_protocol
 *
 * plmysql routines carry MySQL dialect semantics that only hold when the
 * MySQL parser and executor engines are active, which InitParserEngine()
 * and InitExecutorEngine() only select for MySQL-protocol sessions.  Refuse
 * to run rather than silently misinterpret the body.
 *
 * Shared by plmysql_call_handler (named functions/procedures/triggers) and
 * plmysql_inline_handler (anonymous "DO $$ ... $$ LANGUAGE plmysql" blocks)
 * -- both are real compile+execute entry points and both need the same
 * guard; plmysql is a TRUSTED language, so any role with USAGE can reach
 * either one.
 *
 * plmysql_validator() deliberately does NOT call this: pg_restore and
 * logical replication replay DDL over the PostgreSQL protocol, and blocking
 * creation there would break backup/restore for any routine whose CREATE
 * statement reaches this validator at all.
 *
 * That does not mean restore is fully supported over the PG protocol,
 * though.  When check_function_bodies is on (PostgreSQL's default, and
 * pg_dump/pg_restore do not turn it off), plmysql_validator() still calls
 * plmysql_compile(), which validates the body's embedded SQL expressions via
 * check_sql_expr() -> raw_parser() (see pl_gram.c).  raw_parser() dispatches
 * through the *session's* parserengine (parser.c), and InitParserEngine()
 * only selects the MySQL-dialect parser engine for MySQL-protocol sessions
 * -- over the plain PostgreSQL protocol it always falls back to the
 * standard PostgreSQL parser (parsereng.c).  So restoring a plmysql routine
 * whose body actually uses MySQL-dialect SQL (backtick identifiers,
 * MySQL-only builtin functions, etc.) still fails at validation time over
 * the PG protocol; the protocol exemption above only helps routines whose
 * bodies happen to also be valid standard SQL.  Making the validator skip
 * body-checking off-protocol would be a real fix, but that's out of scope
 * here -- deferred to M2.
 */
static void
plmysql_require_mysql_protocol(void)
{
	if (MyProcPort == NULL ||
		nodeTag(MyProcPort->protocol_handler) != T_MySQLProtocol)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("plmysql routines can only be executed over the MySQL protocol"),
				 errhint("Connect to the MySQL listener port instead of the PostgreSQL port.")));
}

/*
 * MySQL permits recursive PROCEDURE calls, controlled per session by
 * max_sp_recursion_depth (zero disables them), but disallows recursive
 * FUNCTION calls altogether.  Count only re-entries of this exact routine:
 * a chain p -> q -> p is recursive for p, while ordinary nested calls are
 * not subject to the limit.
 */
static void
plmysql_check_recursion(PLMySQL_function *func)
{
	PLMySQL_call_stack_entry *entry;
	char		varname[] = "max_sp_recursion_depth";
	char	   *value = NULL;
	int			recursions = 0;
	int			max_depth;

	for (entry = plmysql_call_stack; entry != NULL; entry = entry->prev)
	{
		if (entry->fn_oid == func->fn_oid)
			recursions++;
	}

	if (recursions == 0)
		return;

	if (func->fn_prokind == PROKIND_FUNCTION)
	{
		mysSetPendingMySQLErrno(1424); /* ER_SP_NO_RECURSION */
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("recursive stored functions are not allowed")));
	}

	getSystemVariableValueForSelect(varname, true, &value);
	max_depth = pg_strtoint32(value);

	/* The existing variable catalog predates this enforcement and permits an
	 * unconstrained numeric value.  Keep the server-side limit compatible
	 * with MySQL 5.7 even for clusters upgraded from that catalog. */
	if (max_depth < 0 || max_depth > 255)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("max_sp_recursion_depth must be between 0 and 255")));

	if (recursions > max_depth)
	{
		mysSetPendingMySQLErrno(1456); /* ER_SP_RECURSION_LIMIT */
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("recursive limit %d (as set by the max_sp_recursion_depth variable) was exceeded for routine \"%s\"",
						max_depth, func->fn_signature)));
	}
}

/* ----------
 * plmysql_call_handler
 *
 * The PostgreSQL function manager and trigger manager
 * call this function for execution of PL/MySQL procedures.
 * ----------
 */
PG_FUNCTION_INFO_V1(plmysql_call_handler);

Datum
plmysql_call_handler(PG_FUNCTION_ARGS)
{
	bool		nonatomic;
	PLMySQL_function *func;
	PLMySQL_execstate *save_cur_estate;
	ResourceOwner procedure_resowner;
	PLMySQL_call_stack_entry call_stack_entry;
	PLMySQL_sql_mode_scope sql_mode_scope;
	volatile Datum retval = (Datum) 0;
	int			rc;

	plmysql_require_mysql_protocol();

	nonatomic = fcinfo->context &&
		IsA(fcinfo->context, CallContext) &&
		!castNode(CallContext, fcinfo->context)->atomic;

	sql_mode_scope.saved_mode = mys_sqlMode;
	sql_mode_scope.saved_strict = isStrictTransTablesOn;
	sql_mode_scope.active = false;

	/*
	 * Legacy routines without the metadata GUC retain their caller session
	 * mode.  The proconfig lookup deliberately treats an explicit empty value
	 * as a snapshot, because MySQL uses sql_mode='' to disable all modes.
	 */
	PG_ENSURE_ERROR_CLEANUP(plmysql_sql_mode_error_cleanup,
							PointerGetDatum(&sql_mode_scope));
	{
		char	   *sql_mode_snapshot;

		if (plmysql_get_sql_mode_snapshot(fcinfo->flinfo->fn_oid, &sql_mode_snapshot))
		{
			sql_mode_scope.active = true;
			mysApplySqlMode(sql_mode_snapshot, false);
		}

	/*
	 * Connect to SPI manager
	 */
	if ((rc = SPI_connect_ext(nonatomic ? SPI_OPT_NONATOMIC : 0)) != SPI_OK_CONNECT)
		elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));

	/* Find or compile the function */
	func = plmysql_compile(fcinfo, false);
	plmysql_check_recursion(func);
	call_stack_entry.fn_oid = func->fn_oid;
	call_stack_entry.prev = plmysql_call_stack;
	plmysql_call_stack = &call_stack_entry;

	/* Must save and restore prior value of cur_estate */
	save_cur_estate = func->cur_estate;

	/* Mark the function as busy, so it can't be deleted from under us */
	func->use_count++;

	/*
	 * If we'll need a procedure-lifespan resowner to execute any CALL or DO
	 * statements, create it now.  Since this resowner is not tied to any
	 * parent, failing to free it would result in process-lifespan leaks.
	 * Therefore, be very wary of adding any code between here and the PG_TRY
	 * block.
	 */
	procedure_resowner =
		(nonatomic && func->requires_procedure_resowner) ?
		ResourceOwnerCreate(NULL, "PL/MySQL procedure resources") : NULL;

	PG_TRY();
	{
		/*
		 * Determine if called as function or trigger and call appropriate
		 * subhandler
		 */
		if (CALLED_AS_TRIGGER(fcinfo))
			retval = PointerGetDatum(plmysql_exec_trigger(func,
														  (TriggerData *) fcinfo->context));
		else if (CALLED_AS_EVENT_TRIGGER(fcinfo))
		{
			plmysql_exec_event_trigger(func,
									   (EventTriggerData *) fcinfo->context);
			/* there's no return value in this case */
		}
		else
			retval = plmysql_exec_function(func, fcinfo,
										   NULL, NULL,
										   procedure_resowner,
										   !nonatomic);
	}
	PG_FINALLY();
	{
		plmysql_call_stack = call_stack_entry.prev;

		/* Decrement use-count, restore cur_estate */
		func->use_count--;
		func->cur_estate = save_cur_estate;

		/* Be sure to release the procedure resowner if any */
		if (procedure_resowner)
		{
			ResourceOwnerReleaseAllPlanCacheRefs(procedure_resowner);
			ResourceOwnerDelete(procedure_resowner);
		}
	}
	PG_END_TRY();

	/*
	 * Disconnect from SPI manager
	 */
	if ((rc = SPI_finish()) != SPI_OK_FINISH)
		elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));
	}
	PG_END_ENSURE_ERROR_CLEANUP(plmysql_sql_mode_error_cleanup,
							PointerGetDatum(&sql_mode_scope));

	plmysql_restore_sql_mode(&sql_mode_scope);

	return retval;
}

/* ----------
 * plmysql_inline_handler
 *
 * Called by PostgreSQL to execute an anonymous code block
 * ----------
 */
PG_FUNCTION_INFO_V1(plmysql_inline_handler);

Datum
plmysql_inline_handler(PG_FUNCTION_ARGS)
{
	LOCAL_FCINFO(fake_fcinfo, 0);
	InlineCodeBlock *codeblock = castNode(InlineCodeBlock, DatumGetPointer(PG_GETARG_DATUM(0)));
	PLMySQL_function *func;
	FmgrInfo	flinfo;
	EState	   *simple_eval_estate;
	ResourceOwner simple_eval_resowner;
	Datum		retval;
	int			rc;

	plmysql_require_mysql_protocol();

	/*
	 * Connect to SPI manager
	 */
	if ((rc = SPI_connect_ext(codeblock->atomic ? 0 : SPI_OPT_NONATOMIC)) != SPI_OK_CONNECT)
		elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));

	/* Compile the anonymous code block */
	func = plmysql_compile_inline(codeblock->source_text);

	/* Mark the function as busy, just pro forma */
	func->use_count++;

	/*
	 * Set up a fake fcinfo with just enough info to satisfy
	 * plmysql_exec_function().  In particular note that this sets things up
	 * with no arguments passed.
	 */
	MemSet(fake_fcinfo, 0, SizeForFunctionCallInfo(0));
	MemSet(&flinfo, 0, sizeof(flinfo));
	fake_fcinfo->flinfo = &flinfo;
	flinfo.fn_oid = InvalidOid;
	flinfo.fn_mcxt = CurrentMemoryContext;

	/*
	 * Create a private EState and resowner for simple-expression execution.
	 * Notice that these are NOT tied to transaction-level resources; they
	 * must survive any COMMIT/ROLLBACK the DO block executes, since we will
	 * unconditionally try to clean them up below.  (Hence, be wary of adding
	 * anything that could fail between here and the PG_TRY block.)  See the
	 * comments for shared_simple_eval_estate.
	 *
	 * Because this resowner isn't tied to the calling transaction, we can
	 * also use it as the "procedure" resowner for any CALL statements.  That
	 * helps reduce the opportunities for failure here.
	 */
	simple_eval_estate = CreateExecutorState();
	simple_eval_resowner =
		ResourceOwnerCreate(NULL, "PL/MySQL DO block simple expressions");

	/* And run the function */
	PG_TRY();
	{
		retval = plmysql_exec_function(func, fake_fcinfo,
									   simple_eval_estate,
									   simple_eval_resowner,
									   simple_eval_resowner,	/* see above */
									   codeblock->atomic);
	}
	PG_CATCH();
	{
		/*
		 * We need to clean up what would otherwise be long-lived resources
		 * accumulated by the failed DO block, principally cached plans for
		 * statements (which can be flushed by plmysql_free_function_memory),
		 * execution trees for simple expressions, which are in the private
		 * EState, and cached-plan refcounts held by the private resowner.
		 *
		 * Before releasing the private EState, we must clean up any
		 * simple_econtext_stack entries pointing into it, which we can do by
		 * invoking the subxact callback.  (It will be called again later if
		 * some outer control level does a subtransaction abort, but no harm
		 * is done.)  We cheat a bit knowing that plmysql_subxact_cb does not
		 * pay attention to its parentSubid argument.
		 */
		plmysql_subxact_cb(SUBXACT_EVENT_ABORT_SUB,
						   GetCurrentSubTransactionId(),
						   0, NULL);

		/* Clean up the private EState and resowner */
		FreeExecutorState(simple_eval_estate);
		ResourceOwnerReleaseAllPlanCacheRefs(simple_eval_resowner);
		ResourceOwnerDelete(simple_eval_resowner);

		/* Function should now have no remaining use-counts ... */
		func->use_count--;
		Assert(func->use_count == 0);

		/* ... so we can free subsidiary storage */
		plmysql_free_function_memory(func);

		/* And propagate the error */
		PG_RE_THROW();
	}
	PG_END_TRY();

	/* Clean up the private EState and resowner */
	FreeExecutorState(simple_eval_estate);
	ResourceOwnerReleaseAllPlanCacheRefs(simple_eval_resowner);
	ResourceOwnerDelete(simple_eval_resowner);

	/* Function should now have no remaining use-counts ... */
	func->use_count--;
	Assert(func->use_count == 0);

	/* ... so we can free subsidiary storage */
	plmysql_free_function_memory(func);

	/*
	 * Disconnect from SPI manager
	 */
	if ((rc = SPI_finish()) != SPI_OK_FINISH)
		elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));

	return retval;
}

/* ----------
 * plmysql_validator
 *
 * This function attempts to validate a PL/MySQL function at
 * CREATE FUNCTION time.
 * ----------
 */
PG_FUNCTION_INFO_V1(plmysql_validator);

Datum
plmysql_validator(PG_FUNCTION_ARGS)
{
	Oid			funcoid = PG_GETARG_OID(0);
	HeapTuple	tuple;
	Form_pg_proc proc;
	char		functyptype;
	int			numargs;
	Oid		   *argtypes;
	char	  **argnames;
	char	   *argmodes;
	bool		is_dml_trigger = false;
	bool		is_event_trigger = false;
	int			i;

	if (!CheckFunctionValidatorAccess(fcinfo->flinfo->fn_oid, funcoid))
		PG_RETURN_VOID();

	/* Get the new function's pg_proc entry */
	tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(funcoid));
	if (!HeapTupleIsValid(tuple))
		elog(ERROR, "cache lookup failed for function %u", funcoid);
	proc = (Form_pg_proc) GETSTRUCT(tuple);

	functyptype = get_typtype(proc->prorettype);

	/* Disallow pseudotype result */
	/* except for TRIGGER, EVTTRIGGER, RECORD, VOID, or polymorphic */
	if (functyptype == TYPTYPE_PSEUDO)
	{
		if (proc->prorettype == TRIGGEROID)
			is_dml_trigger = true;
		else if (proc->prorettype == EVENT_TRIGGEROID)
			is_event_trigger = true;
		else if (proc->prorettype != RECORDOID &&
				 proc->prorettype != VOIDOID &&
				 !IsPolymorphicType(proc->prorettype))
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("PL/MySQL functions cannot return type %s",
							format_type_be(proc->prorettype))));
	}

	/* Disallow pseudotypes in arguments (either IN or OUT) */
	/* except for RECORD and polymorphic */
	numargs = get_func_arg_info(tuple,
								&argtypes, &argnames, &argmodes);
	for (i = 0; i < numargs; i++)
	{
		if (get_typtype(argtypes[i]) == TYPTYPE_PSEUDO)
		{
			if (argtypes[i] != RECORDOID &&
				!IsPolymorphicType(argtypes[i]))
				ereport(ERROR,
						(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						 errmsg("PL/MySQL functions cannot accept type %s",
								format_type_be(argtypes[i]))));
		}
	}

	/* Postpone body checks if !check_function_bodies */
	if (check_function_bodies)
	{
		LOCAL_FCINFO(fake_fcinfo, 0);
		FmgrInfo	flinfo;
		int			rc;
		TriggerData trigdata;
		EventTriggerData etrigdata;

		/*
		 * Connect to SPI manager (is this needed for compilation?)
		 */
		if ((rc = SPI_connect()) != SPI_OK_CONNECT)
			elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));

		/*
		 * Set up a fake fcinfo with just enough info to satisfy
		 * plmysql_compile().
		 */
		MemSet(fake_fcinfo, 0, SizeForFunctionCallInfo(0));
		MemSet(&flinfo, 0, sizeof(flinfo));
		fake_fcinfo->flinfo = &flinfo;
		flinfo.fn_oid = funcoid;
		flinfo.fn_mcxt = CurrentMemoryContext;
		if (is_dml_trigger)
		{
			MemSet(&trigdata, 0, sizeof(trigdata));
			trigdata.type = T_TriggerData;
			fake_fcinfo->context = (Node *) &trigdata;
		}
		else if (is_event_trigger)
		{
			MemSet(&etrigdata, 0, sizeof(etrigdata));
			etrigdata.type = T_EventTriggerData;
			fake_fcinfo->context = (Node *) &etrigdata;
		}

		/* Test-compile the function */
		plmysql_compile(fake_fcinfo, true);

		/*
		 * Disconnect from SPI manager
		 */
		if ((rc = SPI_finish()) != SPI_OK_FINISH)
			elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));
	}

	ReleaseSysCache(tuple);

	PG_RETURN_VOID();
}

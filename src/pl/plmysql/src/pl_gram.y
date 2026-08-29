%{
/*-------------------------------------------------------------------------
 *
 * pl_gram.y			- Parser for the PL/MySQL procedural language
 *
 * Portions Copyright (c) 2026, Halo Tech Co.,Ltd.
 * Portions Copyright (c) 1996-2021, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/pl/plmysql/src/pl_gram.y
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "adapter/mysql/errorConvertor.h"

#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "parser/parser.h"
#include "parser/parse_type.h"
#include "parser/scanner.h"
#include "parser/scansup.h"
#include "utils/builtins.h"

#include "plmysql.h"


/* Location tracking support --- simpler than bison's default */
#define YYLLOC_DEFAULT(Current, Rhs, N) \
	do { \
		if (N) \
			(Current) = (Rhs)[1]; \
		else \
			(Current) = (Rhs)[0]; \
	} while (0)

/*
 * Bison doesn't allocate anything that needs to live across parser calls,
 * so we can easily have it use palloc instead of malloc.  This prevents
 * memory leaks if we error out during parsing.  Note this only works with
 * bison >= 2.0.  However, in bison 1.875 the default is to use alloca()
 * if possible, so there's not really much problem anyhow, at least if
 * you're building with gcc.
 */
#define YYMALLOC palloc
#define YYFREE   pfree


typedef struct
{
	int			location;
} sql_error_callback_arg;

#define parser_errposition(pos)  plmysql_scanner_errposition(pos)

union YYSTYPE;					/* need forward reference for tok_is_keyword */

/*
 * MySQL DECLARE HANDLER / SIGNAL support (defined in the trailing section)
 */
static	void			mysql_decl_begin_block(void);
static	List		   *mysql_decl_end_block(void);
static	void			mysql_decl_check_phase(int max_allowed, int location);
static	void			mysql_check_sqlstate_literal(const char *s, int location);
static	int				mysql_make_sqlstate(const char *s);
static	PLMySQL_condition *mysql_resolve_condition_value(const char *name,
														 int location);
static	char		   *mysql_signal_condition_sqlstate(const char *name,
														int location);
static	List		   *mysql_read_signal_items(void);
static	PLMySQL_stmt   *mysql_build_signal_node(int location, bool is_resignal,
												const char *sqlstate, List *items);
static	void			mysql_check_getdiag_items(PLMySQL_stmt_getdiag *stmt,
												  int location);

/*
 * Compile state shared between grammar actions and the helpers: handlers of
 * the block currently being parsed, and the DECLARE-ordering phase.
 */
static	List		   *mysql_current_handlers;
static	int				mysql_decl_phase;

static	bool			tok_is_keyword(int token, union YYSTYPE *lval,
									   int kw_token, const char *kw_str);
static	void			word_is_not_variable(PLword *word, int location);
static	void			cword_is_not_variable(PLcword *cword, int location);
static	void			current_token_is_not_variable(int tok);
static	PLMySQL_expr	*read_sql_construct(int until,
											int until2,
											int until3,
											const char *expected,
											RawParseMode parsemode,
											bool isexpression,
											bool valid_sql,
											int *startloc,
											int *endtoken);
static	PLMySQL_expr	*read_sql_expression(int until,
											 const char *expected);
static	PLMySQL_expr	*read_sql_expression2(int until, int until2,
											  const char *expected,
											  int *endtoken);
static	PLMySQL_expr	*read_sql_stmt(void);
static	PLMySQL_type	*read_datatype(int tok);
static	PLMySQL_stmt	*make_execsql_stmt(int firsttoken, int location,
										   PLword *word);
static	void			mysql_check_dynamic_sql_context(int firsttoken,
													  PLword *word, int location);
static	PLMySQL_stmt_fetch *read_fetch_direction(void);
static	void			 complete_direction(PLMySQL_stmt_fetch *fetch,
											bool *check_FROM);
static	PLMySQL_stmt	*make_return_stmt(int location);
static	PLMySQL_stmt	*make_return_next_stmt(int location);
static	PLMySQL_stmt	*make_return_query_stmt(int location);
static  PLMySQL_stmt	*make_case(int location, PLMySQL_expr *t_expr,
								   List *case_when_list, List *else_stmts);
static	char			*NameOfDatum(PLwdatum *wdatum);
static	void			 check_assignable(PLMySQL_datum *datum, int location);
static	void			 read_into_target(PLMySQL_variable **target,
										  bool *strict);
static	PLMySQL_row		*read_into_scalar_list(char *initial_name,
											   PLMySQL_datum *initial_datum,
											   int initial_location);
static	PLMySQL_row		*make_scalar_list1(char *initial_name,
										   PLMySQL_datum *initial_datum,
										   int lineno, int location);
static	void			 check_sql_expr(const char *stmt,
										RawParseMode parseMode, int location);
static	void			 plmysql_sql_error_callback(void *arg);
static	PLMySQL_type	*parse_datatype(const char *string, int location);
static	void			 check_labels(const char *start_label,
									  const char *end_label,
									  int end_location);
static	PLMySQL_expr	*read_cursor_args(PLMySQL_var *cursor,
										  int until);

%}

%expect 0
%name-prefix="plmysql_yy"
%locations

%union {
		core_YYSTYPE			core_yystype;
		/* these fields must match core_YYSTYPE: */
		int						ival;
		char					*str;
		const char				*keyword;

		PLword					word;
		PLcword					cword;
		PLwdatum				wdatum;
		bool					boolean;
		Oid						oid;
		struct
		{
			char *name;
			int  lineno;
		}						varname;
		struct
		{
			char *name;
			int  lineno;
			PLMySQL_datum   *scalar;
			PLMySQL_datum   *row;
		}						forvariable;
		struct
		{
			char *label;
			int  n_initvars;
			int  *initvarnos;
		}						declhdr;
		PLMySQL_condition		*condition;
		PLMySQL_cond			*cond;
		struct
		{
			List *stmts;
			char *end_label;
			int   end_label_location;
		}						loop_body;
		List					*list;
		PLMySQL_type			*dtype;
		PLMySQL_datum			*datum;
		PLMySQL_var				*var;
		PLMySQL_expr			*expr;
		PLMySQL_stmt			*stmt;
		PLMySQL_exception		*exception;
		PLMySQL_exception_block	*exception_block;
		PLMySQL_nsitem			*nsitem;
		PLMySQL_diag_item		*diagitem;
		PLMySQL_stmt_fetch		*fetch;
		PLMySQL_case_when		*casewhen;
}

%type <declhdr> mysql_decl_sect
%type <varname> decl_varname
%type <list>	decl_varnames
%type <boolean>	exit_type
%type <expr>	decl_defval
%type <dtype>	decl_datatype

%type <expr>	expr_until_semi
%type <expr>	expr_until_then expr_until_loop opt_expr_until_when
%type <expr>	expr_until_end mysql_while_cond
%type <expr>	decl_cursor_query
%type <expr>	opt_exitcond

%type <var>		cursor_variable
%type <forvariable>	for_variable
%type <ival>	foreach_slice
%type <stmt>	for_control

%type <str>		any_identifier opt_block_label opt_loop_label opt_label
%type <str>		option_value

%type <list>	proc_sect stmt_elsifs stmt_else
%type <loop_body>	loop_body
%type <stmt>	proc_stmt pl_block
%type <stmt>	stmt_assign stmt_if stmt_loop stmt_while stmt_exit
%type <stmt>	stmt_return stmt_execsql
%type <stmt>	stmt_dynexecute stmt_for stmt_call stmt_getdiag
%type <stmt>	stmt_open stmt_fetch stmt_move stmt_close stmt_null
%type <stmt>	stmt_commit stmt_rollback
%type <stmt>	stmt_case stmt_foreach_a
%type <stmt>	stmt_repeat stmt_leave stmt_iterate set_item
%type <stmt>	stmt_signal
%type <condition> condition_value
%type <list>	condition_value_list
%type <cond>	decl_condition_def
%type <ival>	decl_handler_type
%type <list>	handler_action_stmt
%type <condition> opt_resignal_cond
%type <list>	opt_signal_setinfo

/*
 * MySQL spells multi-target assignment "SET a = 1, b = 2;", which lowers to a
 * list of plain assignment statements, so stmt_set yields a list and is
 * consumed by proc_sect directly rather than through proc_stmt.
 */
%type <list>	stmt_set set_assign_list

%type <list>	proc_exceptions
%type <exception_block> exception_sect
%type <exception>	proc_exception
%type <condition>	proc_conditions proc_condition

%type <casewhen>	case_when
%type <list>	case_when_list opt_case_else

%type <boolean>	getdiag_area_opt
%type <list>	getdiag_list
%type <diagitem> getdiag_list_item
%type <datum>	getdiag_target
%type <ival>	getdiag_item

%type <fetch>	opt_fetch_direction

%type <ival>	opt_transaction_chain

%type <keyword>	unreserved_keyword


/*
 * Basic non-keyword token types.  These are hard-wired into the core lexer.
 * They must be listed first so that their numeric codes do not depend on
 * the set of keywords.  Keep this list in sync with backend/parser/gram.y!
 *
 * Some of these are not directly referenced in this file, but they must be
 * here anyway.
 */
%token <str>	IDENT UIDENT FCONST SCONST USCONST BCONST XCONST Op
%token <ival>	ICONST PARAM
%token			TYPECAST DOT_DOT COLON_EQUALS EQUALS_GREATER
%token			LESS_EQUALS GREATER_EQUALS NOT_EQUALS

/*
 * Other tokens recognized by plmysql's lexer interface layer (pl_scanner.c).
 */
%token <word>		T_WORD		/* unrecognized simple identifier */
%token <cword>		T_CWORD		/* unrecognized composite identifier */
%token <wdatum>		T_DATUM		/* a VAR, ROW, REC, or RECFIELD variable */
%token				LESS_LESS
%token				GREATER_GREATER

/*
 * Keyword tokens.  Some of these are reserved and some are not;
 * see pl_scanner.c for info.  Be sure unreserved keywords are listed
 * in the "unreserved_keyword" production below.
 */
%token <keyword>	K_ABSOLUTE
%token <keyword>	K_ALL
%token <keyword>	K_AND
%token <keyword>	K_ARRAY
%token <keyword>	K_BACKWARD
%token <keyword>	K_BEGIN
%token <keyword>	K_BY
%token <keyword>	K_CALL
%token <keyword>	K_CASE
%token <keyword>	K_CHAIN
%token <keyword>	K_CLOSE
%token <keyword>	K_COLLATE
%token <keyword>	K_COLUMN
%token <keyword>	K_COLUMN_NAME
%token <keyword>	K_COMMIT
%token <keyword>	K_CONDITION
%token <keyword>	K_CONSTANT
%token <keyword>	K_CONSTRAINT
%token <keyword>	K_CONSTRAINT_NAME
%token <keyword>	K_CONTINUE
%token <keyword>	K_CURRENT
%token <keyword>	K_CURSOR
%token <keyword>	K_DATATYPE
%token <keyword>	K_DEBUG
%token <keyword>	K_DECLARE
%token <keyword>	K_DEFAULT
%token <keyword>	K_DETAIL
%token <keyword>	K_DIAGNOSTICS
%token <keyword>	K_DO
%token <keyword>	K_DUMP
%token <keyword>	K_ELSE
%token <keyword>	K_ELSEIF
%token <keyword>	K_ELSIF
%token <keyword>	K_END
%token <keyword>	K_ERRCODE
%token <keyword>	K_ERROR
%token <keyword>	K_EXCEPTION
%token <keyword>	K_EXECUTE
%token <keyword>	K_EXIT
%token <keyword>	K_FETCH
%token <keyword>	K_FIRST
%token <keyword>	K_FOR
%token <keyword>	K_FOREACH
%token <keyword>	K_FORWARD
%token <keyword>	K_FROM
%token <keyword>	K_GET
%token <keyword>	K_HANDLER
%token <keyword>	K_HINT
%token <keyword>	K_IF
%token <keyword>	K_IMPORT
%token <keyword>	K_IN
%token <keyword>	K_INFO
%token <keyword>	K_INSERT
%token <keyword>	K_INTO
%token <keyword>	K_IS
%token <keyword>	K_ITERATE
%token <keyword>	K_LAST
%token <keyword>	K_LEAVE
%token <keyword>	K_LOG
%token <keyword>	K_LOOP
%token <keyword>	K_MESSAGE
%token <keyword>	K_MESSAGE_TEXT
%token <keyword>	K_MYSQL_ERRNO
%token <keyword>	K_MOVE
%token <keyword>	K_NEXT
%token <keyword>	K_NO
%token <keyword>	K_NOT
%token <keyword>	K_NOTICE
%token <keyword>	K_NULL
%token <keyword>	K_OPEN
%token <keyword>	K_OPTION
%token <keyword>	K_OR
%token <keyword>	K_PG_CONTEXT
%token <keyword>	K_PG_DATATYPE_NAME
%token <keyword>	K_PG_EXCEPTION_CONTEXT
%token <keyword>	K_PG_EXCEPTION_DETAIL
%token <keyword>	K_PG_EXCEPTION_HINT
%token <keyword>	K_PRINT_STRICT_PARAMS
%token <keyword>	K_PRIOR
%token <keyword>	K_QUERY
%token <keyword>	K_RELATIVE
%token <keyword>	K_REPEAT
%token <keyword>	K_RESIGNAL
%token <keyword>	K_RETURN
%token <keyword>	K_RETURNED_SQLSTATE
%token <keyword>	K_REVERSE
%token <keyword>	K_ROLLBACK
%token <keyword>	K_ROW_COUNT
%token <keyword>	K_ROWTYPE
%token <keyword>	K_SCHEMA
%token <keyword>	K_SCHEMA_NAME
%token <keyword>	K_SCROLL
%token <keyword>	K_SET
%token <keyword>	K_SIGNAL
%token <keyword>	K_SLICE
%token <keyword>	K_SQLEXCEPTION
%token <keyword>	K_SQLSTATE
%token <keyword>	K_SQLWARNING
%token <keyword>	K_STACKED
%token <keyword>	K_TABLE
%token <keyword>	K_TABLE_NAME
%token <keyword>	K_THEN
%token <keyword>	K_TO
%token <keyword>	K_TYPE
%token <keyword>	K_UNTIL
%token <keyword>	K_USE_COLUMN
%token <keyword>	K_USE_VARIABLE
%token <keyword>	K_USING
%token <keyword>	K_VARIABLE_CONFLICT
%token <keyword>	K_WARNING
%token <keyword>	K_WHEN
%token <keyword>	K_WHILE

%%

pl_function		: comp_options pl_block opt_semi
					{
						plmysql_parse_result = (PLMySQL_stmt_block *) $2;
					}
				;

comp_options	:
				| comp_options comp_option
				;

comp_option		: '#' K_OPTION K_DUMP
					{
						plmysql_DumpExecTree = true;
					}
				| '#' K_PRINT_STRICT_PARAMS option_value
					{
						if (strcmp($3, "on") == 0)
							plmysql_curr_compile->print_strict_params = true;
						else if (strcmp($3, "off") == 0)
							plmysql_curr_compile->print_strict_params = false;
						else
							elog(ERROR, "unrecognized print_strict_params option %s", $3);
					}
				| '#' K_VARIABLE_CONFLICT K_ERROR
					{
						plmysql_curr_compile->resolve_option = PLMYSQL_RESOLVE_ERROR;
					}
				| '#' K_VARIABLE_CONFLICT K_USE_VARIABLE
					{
						plmysql_curr_compile->resolve_option = PLMYSQL_RESOLVE_VARIABLE;
					}
				| '#' K_VARIABLE_CONFLICT K_USE_COLUMN
					{
						plmysql_curr_compile->resolve_option = PLMYSQL_RESOLVE_COLUMN;
					}
				;

option_value : T_WORD
				{
					$$ = $1.ident;
				}
			 | unreserved_keyword
				{
					$$ = pstrdup($1);
				}

opt_semi		:
				| ';'
				;

/*
 * MySQL spells a block as
 *		[label:] BEGIN [<declarations>] [<statements>] END [label]
 * with the declarations *inside* the block, right after BEGIN, each one an
 * ordinary statement of its own.  (PL/pgSQL puts them before BEGIN instead.)
 *
 * Three mechanisms inherited from the PL/pgSQL original have to survive this
 * repositioning; each is called out where it appears below:
 *
 *	1. opt_block_label's plmysql_ns_push() pairs with the plmysql_ns_pop()
 *	   at the end of this rule.  Exactly one push and one pop per pl_block.
 *	2. plmysql_IdentifierLookup must be IDENTIFIER_LOOKUP_DECLARE while the
 *	   names being declared are scanned, so that the scanner does not resolve
 *	   a name that is only now being declared as a reference to some outer
 *	   variable of the same name, and back to IDENTIFIER_LOOKUP_NORMAL
 *	   afterwards.  Since each DECLARE is a separate statement here, the
 *	   toggle is per-DECLARE rather than per-section.
 *	3. plmysql_add_initdatums(NULL) forgets datums made before this block,
 *	   and plmysql_add_initdatums(&initvarnos) then collects exactly the
 *	   datums this block declared, for block-entry initialization.  The two
 *	   calls must bracket the whole declaration section: the reset lives in
 *	   a mid-rule action right after K_BEGIN so that it runs exactly once per
 *	   block whether or not any DECLARE follows, and the collect lives in
 *	   mysql_decl_sect, which likewise reduces exactly once per block.  (Do
 *	   not move the reset into mysql_decl_stmt: it would then run once per
 *	   DECLARE, and each run would drop the variables declared by the
 *	   preceding DECLAREs of the same block out of initvarnos, leaving them
 *	   uninitialized at block entry.)
 */
pl_block		: opt_block_label K_BEGIN
					{
						/* Forget any variables created before this block */
						plmysql_add_initdatums(NULL);
						mysql_decl_begin_block();
					}
				  mysql_decl_sect proc_sect exception_sect K_END opt_label
					{
						PLMySQL_stmt_block *new;

						new = palloc0(sizeof(PLMySQL_stmt_block));

						new->cmd_type	= PLMYSQL_STMT_BLOCK;
						new->lineno		= plmysql_location_to_lineno(@2);
						new->stmtid		= ++plmysql_curr_compile->nstatements;
						new->label		= $1;
						new->n_initvars = $4.n_initvars;
						new->initvarnos = $4.initvarnos;
						new->body		= $5;
						new->exceptions	= $6;
						new->handlers	= mysql_decl_end_block();

						check_labels($1, $8, @8);
						plmysql_ns_pop();

						$$ = (PLMySQL_stmt *)new;
					}
				;


mysql_decl_sect	:
					{
						$$.label	  = NULL;
						$$.n_initvars = 0;
						$$.initvarnos = NULL;
					}
				| mysql_decl_stmts
					{
						$$.label	  = NULL;
						/* Remember variables declared in mysql_decl_stmts */
						$$.n_initvars = plmysql_add_initdatums(&($$.initvarnos));
					}
				;

mysql_decl_stmts : mysql_decl_stmts mysql_decl_stmt
				| mysql_decl_stmt
				;

/*
 * DECLARE var[, var...] type [DEFAULT expr];
 *
 * Unlike PL/pgSQL's declaration syntax, one DECLARE can name several
 * variables of the same type.
 */
mysql_decl_stmt	: mysql_decl_head decl_varnames decl_datatype decl_defval
					{
						ListCell   *lc;
						int			lineno = plmysql_location_to_lineno(@1);

						/*
						 * decl_defval has already eaten the terminating
						 * semicolon (either directly, or via the
						 * read_sql_expression() that reads the default
						 * expression), and this reduction is likewise
						 * bison's default action for its state, so no
						 * further token has been scanned yet: resuming
						 * identifier lookup here takes effect before the
						 * first token of whatever follows is read.
						 */
						plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;

						mysql_decl_check_phase(0, @1);

						/* $2 is the decl_varnames list (mysql_decl_head is $1) */
						foreach(lc, $2)
						{
							char			 *name = strVal(lfirst(lc));
							PLMySQL_variable *var;
							PLMySQL_type	 *typ;

							/*
							 * plmysql_build_variable() takes ownership of the
							 * PLMySQL_type it is handed and may modify it, so
							 * when one DECLARE names several variables each
							 * one needs its own copy rather than a shared
							 * pointer to the struct decl_datatype built.
							 *
							 * The default-value expression, in contrast, is
							 * deliberately shared: PLMySQL_expr is read-only
							 * once built, and exec_stmt_block() evaluates it
							 * separately for each variable it initializes.
							 */
							typ = palloc(sizeof(PLMySQL_type));
							memcpy(typ, $3, sizeof(PLMySQL_type));

							var = plmysql_build_variable(name, lineno,
														 typ, true);
							var->default_val = $4;
						}
					}
				|
				  /*
				   * MySQL cursor declaration:
				   * "DECLARE c CURSOR FOR select_statement;"
				   *
				   * Ported from plpgsql's cursor declarations minus the
				   * argument list (MySQL cursors take no arguments) and the
				   * scroll options (MySQL cursors are never scrollable).  The
				   * variable is a refcursor whose default value is its own
				   * name, so OPEN c opens a portal named after the variable
				   * unless the body assigns it something else.
				   */
				  mysql_decl_head decl_varname K_CURSOR K_FOR decl_cursor_query
					{
						PLMySQL_var		*new;
						PLMySQL_expr	*curname_def;
						char			buf[NAMEDATALEN * 2 + 64];
						char		   *cp1;
						char		   *cp2;

						/*
						 * read_sql_stmt() saved and restored the lookup flag
						 * around the query text, so it reads DECLARE here;
						 * resume normal lookup before anything else is
						 * scanned.
						 */
						plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;

						mysql_decl_check_phase(1, @1);

						new = (PLMySQL_var *)
							plmysql_build_variable($2.name, $2.lineno,
												   plmysql_build_datatype(REFCURSOROID,
																		  -1,
																		  InvalidOid,
																		  NULL),
												   true);

						curname_def = palloc0(sizeof(PLMySQL_expr));

						/* Note: refname has been truncated to NAMEDATALEN */
						cp1 = new->refname;
						cp2 = buf;
						/*
						 * Don't trust standard_conforming_strings here;
						 * it might change before we use the string.
						 */
						if (strchr(cp1, '\\') != NULL)
							*cp2++ = ESCAPE_STRING_SYNTAX;
						*cp2++ = '\'';
						while (*cp1)
						{
							if (SQL_STR_DOUBLE(*cp1, true))
								*cp2++ = *cp1;
							*cp2++ = *cp1++;
						}
						strcpy(cp2, "'::pg_catalog.refcursor");
						curname_def->query = pstrdup(buf);
						curname_def->parseMode = RAW_PARSE_PLPGSQL_EXPR;
						new->default_val = curname_def;

						new->cursor_explicit_expr = $5;
						new->cursor_explicit_argrow = -1;
						new->cursor_options = CURSOR_OPT_FAST_PLAN |
											  CURSOR_OPT_NO_SCROLL;
					}
				|
				  /*
				   * MySQL named condition:
				   * "DECLARE cond CONDITION FOR <errno | SQLSTATE 'xxxxx'>;"
				   *
				   * Becomes a COND datum registered in the block's namespace
				   * so HANDLER and SIGNAL statements can refer to it by name.
				   */
				  mysql_decl_head decl_varname K_CONDITION K_FOR decl_condition_def
					{
						PLMySQL_cond	   *cond = $5;

						mysql_decl_check_phase(0, @3);

						cond->dtype = PLMYSQL_DTYPE_COND;
						cond->refname = $2.name;
						cond->lineno = $2.lineno;
						plmysql_adddatum((PLMySQL_datum *) cond);
						plmysql_ns_additem(PLMYSQL_NSTYPE_VAR, cond->dno,
										   cond->refname);
					}
				|
				  /*
				   * MySQL condition handler:
				   * "DECLARE {CONTINUE|EXIT} HANDLER FOR <conds> <stmt>;"
				   *
				   * The action statement is parsed with normal identifier
				   * lookup (the mid-rule resumes it), since handler bodies
				   * reference variables like any other statement.
				   */
				  mysql_decl_head decl_handler_type K_HANDLER K_FOR condition_value_list
					{
						plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
						mysql_decl_check_phase(2, @2);
					}
				  handler_action_stmt
					{
						PLMySQL_handler *h = palloc0(sizeof(PLMySQL_handler));

						h->lineno = plmysql_location_to_lineno(@2);
						h->is_continue = ($2 == K_CONTINUE);
						h->conditions = $5;
						h->action = $7;
						plmysql_curr_compile->has_handlers = true;

						mysql_current_handlers = lappend(mysql_current_handlers, h);
					}
				;

/*
 * Shared head of both DECLARE forms.  An own nonterminal (rather than a
 * mid-rule action in each alternative) is what keeps the scanner-lookup
 * switch conflict-free: after K_DECLARE, reducing this empty-headed rule is
 * the only action, so the flag is set before the first declared name is
 * scanned -- the same guarantee the variable branch relied on when it was
 * the only DECLARE form.
 */
mysql_decl_head	: K_DECLARE
					{
						plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
					}
				;

decl_cursor_query :
					{ $$ = read_sql_stmt(); }
				;

decl_condition_def : K_SQLSTATE SCONST ';'
					{
						PLMySQL_cond *cond = palloc0(sizeof(PLMySQL_cond));

						mysql_check_sqlstate_literal($2, @2);
						strcpy(cond->sqlstate, $2);
						$$ = cond;
					}
				| ICONST ';'
					{
						/*
						 * MySQL errno (e.g. 1062 for duplicate key).  The
						 * SQLSTATE is not fixed here; the matcher matches by
						 * errno and SIGNAL by name reverse-maps it.
						 */
						PLMySQL_cond *cond = palloc0(sizeof(PLMySQL_cond));

						cond->mysql_errno = $1;
						$$ = cond;
					}
				;

decl_handler_type : K_CONTINUE
					{
						$$ = K_CONTINUE;
					}
				| K_EXIT
					{
						$$ = K_EXIT;
					}
				;

/*
 * One value of a HANDLER's condition list.
 */
condition_value	: K_SQLSTATE SCONST
					{
						PLMySQL_condition *cond = palloc0(sizeof(PLMySQL_condition));

						mysql_check_sqlstate_literal($2, @2);
						cond->sqlerrstate = mysql_make_sqlstate($2);
						cond->condname = psprintf("SQLSTATE '%s'", $2);
						$$ = cond;
					}
				| ICONST
					{
						PLMySQL_condition *cond = palloc0(sizeof(PLMySQL_condition));

						cond->mysql_errno = $1;
						cond->condname = psprintf("errno %d", $1);
						$$ = cond;
					}
				| K_NOT T_WORD
					{
						/* MySQL's "NOT FOUND" class condition */
						PLMySQL_condition *cond = palloc0(sizeof(PLMySQL_condition));

						if ($2.quoted || pg_strcasecmp($2.ident, "found") != 0)
							yyerror("unrecognized condition name");
						cond->sqlerrstate = ERRCODE_NO_DATA;
						cond->condname = pstrdup("NOT FOUND");
						$$ = cond;
					}
				| K_SQLEXCEPTION
					{
						PLMySQL_condition *cond = palloc0(sizeof(PLMySQL_condition));

						cond->sqlerrstate = PLMYSQL_COND_SQLEXCEPTION;
						cond->condname = pstrdup("SQLEXCEPTION");
						$$ = cond;
					}
				| K_SQLWARNING
					{
						PLMySQL_condition *cond = palloc0(sizeof(PLMySQL_condition));

						cond->sqlerrstate = ERRCODE_WARNING;
						cond->condname = pstrdup("SQLWARNING");
						$$ = cond;
					}
				| any_identifier
					{
						$$ = mysql_resolve_condition_value($1, @1);
					}
				;

condition_value_list : condition_value_list ',' condition_value
					{
						$$ = lappend($1, $3);
					}
				| condition_value
					{
						$$ = list_make1($1);
					}
				;

handler_action_stmt : proc_stmt
					{
						/* don't bother linking null statements into the list */
						$$ = $1 ? list_make1($1) : NIL;
					}
				| stmt_set
					{
						/* covers "SET a = expr" and "SET a = expr, b = expr" */
						$$ = $1;
					}
				;

decl_varnames	: decl_varname
					{
						$$ = list_make1(makeString($1.name));
					}
				| decl_varnames ',' decl_varname
					{
						ListCell   *lc;

						/*
						 * decl_varname rejects a name that is already
						 * declared in this block, but the variables of this
						 * DECLARE are not built until the whole statement has
						 * been reduced, so that check cannot see the names
						 * listed earlier in this same DECLARE.  Close the gap
						 * here, so that every name is checked against every
						 * name preceding it in the block.
						 */
						foreach(lc, $1)
						{
							if (strcmp(strVal(lfirst(lc)), $3.name) == 0)
								yyerror("duplicate declaration");
						}

						$$ = lappend($1, makeString($3.name));
					}
				;

decl_varname	: T_WORD
					{
						$$.name = $1.ident;
						$$.lineno = plmysql_location_to_lineno(@1);
						/*
						 * Check to make sure name isn't already declared
						 * in the current block.
						 */
						if (plmysql_ns_lookup(plmysql_ns_top(), true,
											  $1.ident, NULL, NULL,
											  NULL) != NULL)
							yyerror("duplicate declaration");

						if (plmysql_curr_compile->extra_warnings & PLMYSQL_XCHECK_SHADOWVAR ||
							plmysql_curr_compile->extra_errors & PLMYSQL_XCHECK_SHADOWVAR)
						{
							PLMySQL_nsitem *nsi;
							nsi = plmysql_ns_lookup(plmysql_ns_top(), false,
													$1.ident, NULL, NULL, NULL);
							if (nsi != NULL)
								ereport(plmysql_curr_compile->extra_errors & PLMYSQL_XCHECK_SHADOWVAR ? ERROR : WARNING,
										(errcode(ERRCODE_DUPLICATE_ALIAS),
										 errmsg("variable \"%s\" shadows a previously defined variable",
												$1.ident),
										 parser_errposition(@1)));
						}

					}
				| unreserved_keyword
					{
						$$.name = pstrdup($1);
						$$.lineno = plmysql_location_to_lineno(@1);
						/*
						 * Check to make sure name isn't already declared
						 * in the current block.
						 */
						if (plmysql_ns_lookup(plmysql_ns_top(), true,
											  $1, NULL, NULL,
											  NULL) != NULL)
							yyerror("duplicate declaration");

						if (plmysql_curr_compile->extra_warnings & PLMYSQL_XCHECK_SHADOWVAR ||
							plmysql_curr_compile->extra_errors & PLMYSQL_XCHECK_SHADOWVAR)
						{
							PLMySQL_nsitem *nsi;
							nsi = plmysql_ns_lookup(plmysql_ns_top(), false,
													$1, NULL, NULL, NULL);
							if (nsi != NULL)
								ereport(plmysql_curr_compile->extra_errors & PLMYSQL_XCHECK_SHADOWVAR ? ERROR : WARNING,
										(errcode(ERRCODE_DUPLICATE_ALIAS),
										 errmsg("variable \"%s\" shadows a previously defined variable",
												$1),
										 parser_errposition(@1)));
						}

					}
				;

decl_datatype	:
					{
						/*
						 * If there's a lookahead token, read_datatype
						 * should consume it.
						 */
						$$ = read_datatype(yychar);
						yyclearin;
					}
				;

decl_defval		: ';'
					{ $$ = NULL; }
				| decl_defkey
					{
						$$ = read_sql_expression(';', ";");
					}
				;

decl_defkey		: assign_operator
				| K_DEFAULT
				;

/*
 * Ada-based PL/SQL uses := for assignment and variable defaults, while
 * the SQL standard uses equals for these cases and for GET
 * DIAGNOSTICS, so we support both.  FOR and OPEN only support :=.
 */
assign_operator	: '='
				| COLON_EQUALS
				;

proc_sect		:
					{ $$ = NIL; }
				| proc_sect proc_stmt
					{
						/* don't bother linking null statements into list */
						if ($2 == NULL)
							$$ = $1;
						else
							$$ = lappend($1, $2);
					}
				| proc_sect stmt_set
					{
						/*
						 * A MySQL "SET a = expr, b = expr;" statement lowers
						 * to one assignment per target, all appended here.
						 */
						$$ = list_concat($1, $2);
					}
				;

proc_stmt		: pl_block ';'
						{ $$ = $1; }
				| stmt_assign
						{ $$ = $1; }
				| stmt_if
						{ $$ = $1; }
				| stmt_case
						{ $$ = $1; }
				| stmt_loop
						{ $$ = $1; }
				| stmt_while
						{ $$ = $1; }
				| stmt_repeat
						{ $$ = $1; }
				| stmt_leave
						{ $$ = $1; }
				| stmt_iterate
						{ $$ = $1; }
				| stmt_for
						{ $$ = $1; }
				| stmt_foreach_a
						{ $$ = $1; }
				| stmt_exit
						{ $$ = $1; }
				| stmt_signal
						{ $$ = $1; }
				| stmt_return
						{ $$ = $1; }
				| stmt_execsql
						{ $$ = $1; }
				| stmt_dynexecute
						{ $$ = $1; }
				| stmt_call
						{ $$ = $1; }
				| stmt_getdiag
						{ $$ = $1; }
				| stmt_open
						{ $$ = $1; }
				| stmt_fetch
						{ $$ = $1; }
				| stmt_move
						{ $$ = $1; }
				| stmt_close
						{ $$ = $1; }
				| stmt_null
						{ $$ = $1; }
				| stmt_commit
						{ $$ = $1; }
				| stmt_rollback
						{ $$ = $1; }
				;

stmt_call		: K_CALL
					{
						PLMySQL_stmt_call *new;

						new = palloc0(sizeof(PLMySQL_stmt_call));
						new->cmd_type = PLMYSQL_STMT_CALL;
						new->lineno = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						plmysql_push_back_token(K_CALL);
						new->expr = read_sql_stmt();
						new->is_call = true;

						/* Remember we may need a procedure resource owner */
						plmysql_curr_compile->requires_procedure_resowner = true;

						$$ = (PLMySQL_stmt *)new;

					}
				| K_DO
					{
						/* use the same structures as for CALL, for simplicity */
						PLMySQL_stmt_call *new;

						new = palloc0(sizeof(PLMySQL_stmt_call));
						new->cmd_type = PLMYSQL_STMT_CALL;
						new->lineno = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						plmysql_push_back_token(K_DO);
						new->expr = read_sql_stmt();
						new->is_call = false;

						/* Remember we may need a procedure resource owner */
						plmysql_curr_compile->requires_procedure_resowner = true;

						$$ = (PLMySQL_stmt *)new;

					}
				;

stmt_assign		: T_DATUM
					{
						PLMySQL_stmt_assign *new;
						RawParseMode pmode;

						/* see how many names identify the datum */
						switch ($1.ident ? 1 : list_length($1.idents))
						{
							case 1:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN1;
								break;
							case 2:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN2;
								break;
							case 3:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN3;
								break;
							default:
								elog(ERROR, "unexpected number of names");
								pmode = 0; /* keep compiler quiet */
						}

						check_assignable($1.datum, @1);
						new = palloc0(sizeof(PLMySQL_stmt_assign));
						new->cmd_type = PLMYSQL_STMT_ASSIGN;
						new->lineno   = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						new->varno = $1.datum->dno;
						/* Push back the head name to include it in the stmt */
						plmysql_push_back_token(T_DATUM);
						new->expr = read_sql_construct(';', 0, 0, ";",
													   pmode,
													   false, true,
													   NULL, NULL);

						$$ = (PLMySQL_stmt *)new;
					}
				;

/*
 * MySQL spells assignment "SET var = expr;" and also allows several targets
 * in one statement: "SET a = 1, b = 2;".  Everything after each target name
 * is handled exactly as stmt_assign handles a bare "var := expr;": the target
 * datum token is pushed back so that read_sql_construct() captures the whole
 * "var = expr" text and hands it to the core parser in the matching
 * RAW_PARSE_PLPGSQL_ASSIGNn mode.  Each target lowers to one assignment
 * statement, executed in source order.
 *
 * The T_WORD/T_CWORD alternatives exist only to turn "SET notavariable = 1"
 * into a message naming the offending word, instead of a bare syntax error;
 * this mirrors what getdiag_target does.
 *
 * MySQL also allows "SET @uservar = expr;": a session-level user variable,
 * not a plmysql local datum.  The scanner has no notion of "@identifier" as
 * one token (core scan.l returns a lone "@" as a generic Op, since it isn't
 * one of the core scanner's multi-char operators), so "SET @x = 1" reaches
 * this production as K_SET Op("@") rather than K_SET T_DATUM.  Rather than
 * teach this grammar what a user variable is, the whole statement is handed
 * to SPI verbatim, exactly like a generic passthrough SQL statement
 * (stmt_execsql's make_execsql_stmt): under the MySQL protocol session that
 * every plmysql routine runs in, SPI parses it with the very same grammar
 * that already handles a top-level "SET @uservar = expr;", so the existing
 * user-variable machinery runs it unchanged.
 *
 * "SET <system-var> = expr" (no "@") is not covered by this: that spelling
 * is indistinguishable at this point from "SET <bad-local-var-name> = expr",
 * which the T_WORD/T_CWORD alternatives below deliberately reject with a
 * friendlier error instead of guessing. Left for a future pass.
 */
stmt_set		: K_SET set_assign_list
					{
						$$ = $2;
					}
				| K_SET Op
					{
						/* "SET @uservar = expr;" -- see the comment above */
						if (strcmp($2, "@") != 0)
							yyerror("syntax error");
						plmysql_push_back_token(Op);
						$$ = list_make1(make_execsql_stmt(K_SET, @1, NULL));
					}
				| K_SET T_WORD
					{
						/* just to give a better message than "syntax error" */
						word_is_not_variable(&($2), @2);
						$$ = NIL;
					}
				| K_SET T_CWORD
					{
						/* just to give a better message than "syntax error" */
						cword_is_not_variable(&($2), @2);
						$$ = NIL;
					}
				;

set_assign_list	: set_item
					{
						$$ = list_make1($1);
					}
				| set_item ',' set_assign_list
					{
						$$ = lcons($1, $3);
					}
				;

set_item		: T_DATUM
					{
						PLMySQL_stmt_assign *new;
						RawParseMode pmode;
						int			endtok;

						/* see how many names identify the datum */
						switch ($1.ident ? 1 : list_length($1.idents))
						{
							case 1:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN1;
								break;
							case 2:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN2;
								break;
							case 3:
								pmode = RAW_PARSE_PLPGSQL_ASSIGN3;
								break;
							default:
								elog(ERROR, "unexpected number of names");
								pmode = 0; /* keep compiler quiet */
						}

						check_assignable($1.datum, @1);
						new = palloc0(sizeof(PLMySQL_stmt_assign));
						new->cmd_type = PLMYSQL_STMT_ASSIGN;
						new->lineno   = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						new->varno = $1.datum->dno;
						/* Push back the head name to include it in the stmt */
						plmysql_push_back_token(T_DATUM);
						new->expr = read_sql_construct(0, ',', ';',
													   "\",\" or \";\"",
													   pmode,
													   false, true,
													   NULL, &endtok);

						/*
						 * read_sql_construct() consumed the delimiter that
						 * ended this item.  A comma has to be handed back so
						 * the enclosing set_assign_list can shift it and
						 * parse the next target; a semicolon is this
						 * statement's own terminator and stays consumed.
						 */
						if (endtok == ',')
							plmysql_push_back_token(',');

						$$ = (PLMySQL_stmt *)new;
					}
				;

/*
 * MySQL: "SIGNAL SQLSTATE 'xxxxx' [SET ...];" /
 *        "SIGNAL condition_name [SET ...];" /
 *        "RESIGNAL [SQLSTATE 'xxxxx' | condition_name] [SET ...];"
 *
 * The SET items (MESSAGE_TEXT, MYSQL_ERRNO) are read by a C helper that
 * consumes the whole clause and hands the terminating ';' back to the
 * grammar.
 */
stmt_signal		: K_SIGNAL K_SQLSTATE SCONST opt_signal_setinfo ';'
					{
						mysql_check_sqlstate_literal($3, @3);
						$$ = mysql_build_signal_node(@1, false, $3, $4);
					}
				| K_SIGNAL any_identifier opt_signal_setinfo ';'
					{
						$$ = mysql_build_signal_node(@1, false,
													 mysql_signal_condition_sqlstate($2, @2),
													 $3);
					}
				| K_RESIGNAL opt_resignal_cond opt_signal_setinfo ';'
					{
						/*
						 * RESIGNAL re-raises the condition that activated the
						 * handler; a condition value here overrides the
						 * SQLSTATE (optionally with new SET items).
						 */
						$$ = mysql_build_signal_node(@1, true,
													 ($2 ? $2->condname : NULL),
													 $3);
					}
				;

opt_resignal_cond : K_SQLSTATE SCONST
					{
						/*
						 * The condition struct's condname field carries the
						 * SQLSTATE text here, as the override value.
						 */
						PLMySQL_condition *cond = palloc0(sizeof(PLMySQL_condition));

						mysql_check_sqlstate_literal($2, @2);
						cond->sqlerrstate = mysql_make_sqlstate($2);
						cond->condname = pstrdup($2);
						$$ = cond;
					}
				| any_identifier
					{
						PLMySQL_condition *cond;

						cond = mysql_resolve_condition_value($1, @1);
						if (cond->sqlerrstate == PLMYSQL_COND_SQLEXCEPTION ||
							ERRCODE_IS_CATEGORY(cond->sqlerrstate))
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("RESIGNAL cannot use a condition class"),
									 parser_errposition(@1)));
						$$ = cond;
					}
				| /*EMPTY*/
					{
						$$ = NULL;
					}
				;

/*
 * "SET MESSAGE_TEXT = ..., MYSQL_ERRNO = ..." of a SIGNAL statement.  Empty
 * unless the K_SET keyword is actually present.  The helper leaves the
 * terminating ';' for the grammar to shift.
 */
opt_signal_setinfo :
					{
						$$ = mysql_read_signal_items();
					}
				;

stmt_getdiag	: K_GET getdiag_area_opt K_DIAGNOSTICS getdiag_list ';'
					{
						PLMySQL_stmt_getdiag	 *new;

						new = palloc0(sizeof(PLMySQL_stmt_getdiag));
						new->cmd_type = PLMYSQL_STMT_GETDIAG;
						new->lineno   = plmysql_location_to_lineno(@1);
						new->stmtid	  = ++plmysql_curr_compile->nstatements;
						new->is_stacked = $2;
						new->diag_items = $4;
						mysql_check_getdiag_items(new, @1);

						$$ = (PLMySQL_stmt *)new;
					}
				;

stmt_getdiag	: K_GET getdiag_area_opt K_DIAGNOSTICS K_CONDITION ICONST getdiag_list ';'
					{
						/*
						 * MySQL's "GET [CURRENT|STACKED] DIAGNOSTICS
						 * CONDITION <n> <items>".  PostgreSQL's diagnostics
						 * area holds a single condition, so only CONDITION 1
						 * is accepted at run time; the items are read from
						 * the handler's error the same way STACKED does.
						 */
						PLMySQL_stmt_getdiag	 *new;

						new = palloc0(sizeof(PLMySQL_stmt_getdiag));
						new->cmd_type = PLMYSQL_STMT_GETDIAG;
						new->lineno   = plmysql_location_to_lineno(@1);
						new->stmtid	  = ++plmysql_curr_compile->nstatements;
						new->is_stacked = $2;
						new->is_condition = true;
						new->condition_no = $5;
						new->diag_items = $6;
						mysql_check_getdiag_items(new, @1);
						$$ = (PLMySQL_stmt *)new;
					}
				;

getdiag_area_opt :
					{
						$$ = false;
					}
				| K_CURRENT
					{
						$$ = false;
					}
				| K_STACKED
					{
						$$ = true;
					}
				;

getdiag_list : getdiag_list ',' getdiag_list_item
					{
						$$ = lappend($1, $3);
					}
				| getdiag_list_item
					{
						$$ = list_make1($1);
					}
				;

getdiag_list_item : getdiag_target assign_operator getdiag_item
					{
						PLMySQL_diag_item *new;

						new = palloc(sizeof(PLMySQL_diag_item));
						new->target = $1->dno;
						new->kind = $3;

						$$ = new;
					}
				;

getdiag_item :
					{
						int	tok = yylex();

						if (tok_is_keyword(tok, &yylval,
										   K_ROW_COUNT, "row_count"))
							$$ = PLMYSQL_GETDIAG_ROW_COUNT;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_CONTEXT, "pg_context"))
							$$ = PLMYSQL_GETDIAG_CONTEXT;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_EXCEPTION_DETAIL, "pg_exception_detail"))
							$$ = PLMYSQL_GETDIAG_ERROR_DETAIL;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_EXCEPTION_HINT, "pg_exception_hint"))
							$$ = PLMYSQL_GETDIAG_ERROR_HINT;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_EXCEPTION_CONTEXT, "pg_exception_context"))
							$$ = PLMYSQL_GETDIAG_ERROR_CONTEXT;
						else if (tok_is_keyword(tok, &yylval,
												K_COLUMN_NAME, "column_name"))
							$$ = PLMYSQL_GETDIAG_COLUMN_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_CONSTRAINT_NAME, "constraint_name"))
							$$ = PLMYSQL_GETDIAG_CONSTRAINT_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_PG_DATATYPE_NAME, "pg_datatype_name"))
							$$ = PLMYSQL_GETDIAG_DATATYPE_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_MESSAGE_TEXT, "message_text"))
							$$ = PLMYSQL_GETDIAG_MESSAGE_TEXT;
						else if (tok_is_keyword(tok, &yylval,
												K_TABLE_NAME, "table_name"))
							$$ = PLMYSQL_GETDIAG_TABLE_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_SCHEMA_NAME, "schema_name"))
							$$ = PLMYSQL_GETDIAG_SCHEMA_NAME;
						else if (tok_is_keyword(tok, &yylval,
												K_RETURNED_SQLSTATE, "returned_sqlstate"))
							$$ = PLMYSQL_GETDIAG_RETURNED_SQLSTATE;
						else if (tok_is_keyword(tok, &yylval,
												K_MYSQL_ERRNO, "mysql_errno"))
							$$ = PLMYSQL_GETDIAG_MYSQL_ERRNO;
						else
							yyerror("unrecognized GET DIAGNOSTICS item");
					}
				;

getdiag_target	: T_DATUM
					{
						/*
						 * In principle we should support a getdiag_target
						 * that is an array element, but for now we don't, so
						 * just throw an error if next token is '['.
						 */
						if ($1.datum->dtype == PLMYSQL_DTYPE_ROW ||
							$1.datum->dtype == PLMYSQL_DTYPE_REC ||
							plmysql_peek() == '[')
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("\"%s\" is not a scalar variable",
											NameOfDatum(&($1))),
									 parser_errposition(@1)));
						check_assignable($1.datum, @1);
						$$ = $1.datum;
					}
				| T_WORD
					{
						/* just to give a better message than "syntax error" */
						word_is_not_variable(&($1), @1);
					}
				| T_CWORD
					{
						/* just to give a better message than "syntax error" */
						cword_is_not_variable(&($1), @1);
					}
				;

stmt_if			: K_IF expr_until_then proc_sect stmt_elsifs stmt_else K_END K_IF ';'
					{
						PLMySQL_stmt_if *new;

						new = palloc0(sizeof(PLMySQL_stmt_if));
						new->cmd_type	= PLMYSQL_STMT_IF;
						new->lineno		= plmysql_location_to_lineno(@1);
						new->stmtid		= ++plmysql_curr_compile->nstatements;
						new->cond		= $2;
						new->then_body	= $3;
						new->elsif_list = $4;
						new->else_body  = $5;

						$$ = (PLMySQL_stmt *)new;
					}
				;

stmt_elsifs		:
					{
						$$ = NIL;
					}
				| stmt_elsifs elseif_key expr_until_then proc_sect
					{
						PLMySQL_if_elsif *new;

						new = palloc0(sizeof(PLMySQL_if_elsif));
						new->lineno = plmysql_location_to_lineno(@2);
						new->cond   = $3;
						new->stmts  = $4;

						$$ = lappend($1, new);
					}
				;

/*
 * MySQL spells this ELSEIF.  Task 4 moved "elseif" out of the unreserved
 * keyword table and into the reserved one as K_ELSEIF, where the core
 * scanner resolves it before the unreserved table is ever consulted, so the
 * inherited K_ELSIF production alone no longer accepts MySQL's spelling.
 * Only "elsif" remains in the unreserved table (pl_unreserved_kwlist.h),
 * still resolving to K_ELSIF; "elseif" is now reserved-only
 * (pl_reserved_kwlist.h), resolving to K_ELSEIF.  Accept both spellings
 * here: K_ELSIF is what "elsif" still lexes to.
 */
elseif_key		: K_ELSEIF
				| K_ELSIF
				;

stmt_else		:
					{
						$$ = NIL;
					}
				| K_ELSE proc_sect
					{
						$$ = $2;
					}
				;

stmt_case		: K_CASE opt_expr_until_when case_when_list opt_case_else K_END K_CASE ';'
					{
						$$ = make_case(@1, $2, $3, $4);
					}
				;

opt_expr_until_when	:
					{
						PLMySQL_expr *expr = NULL;
						int	tok = yylex();

						if (tok != K_WHEN)
						{
							plmysql_push_back_token(tok);
							expr = read_sql_expression(K_WHEN, "WHEN");
						}
						plmysql_push_back_token(K_WHEN);
						$$ = expr;
					}
				;

case_when_list	: case_when_list case_when
					{
						$$ = lappend($1, $2);
					}
				| case_when
					{
						$$ = list_make1($1);
					}
				;

case_when		: K_WHEN expr_until_then proc_sect
					{
						PLMySQL_case_when *new = palloc(sizeof(PLMySQL_case_when));

						new->lineno	= plmysql_location_to_lineno(@1);
						new->expr	= $2;
						new->stmts	= $3;
						$$ = new;
					}
				;

opt_case_else	:
					{
						$$ = NIL;
					}
				| K_ELSE proc_sect
					{
						/*
						 * proc_sect could return an empty list, but we
						 * must distinguish that from not having ELSE at all.
						 * Simplest fix is to return a list with one NULL
						 * pointer, which make_case() must take care of.
						 */
						if ($2 != NIL)
							$$ = $2;
						else
							$$ = list_make1(NULL);
					}
				;

stmt_loop		: opt_loop_label K_LOOP loop_body
					{
						PLMySQL_stmt_loop *new;

						new = palloc0(sizeof(PLMySQL_stmt_loop));
						new->cmd_type = PLMYSQL_STMT_LOOP;
						new->lineno   = plmysql_location_to_lineno(@2);
						new->stmtid   = ++plmysql_curr_compile->nstatements;
						new->label	  = $1;
						new->body	  = $3.stmts;

						check_labels($1, $3.end_label, $3.end_label_location);
						plmysql_ns_pop();

						$$ = (PLMySQL_stmt *)new;
					}
				;

/*
 * The condition of a WHILE loop can be terminated either by MySQL's "DO" or
 * by the inherited plpgsql-style "LOOP".  One empty production reads the
 * condition up to whichever delimiter appears first and pushes that delimiter
 * back, so the surrounding stmt_while productions can shift it and use it to
 * tell the two forms apart without a reduce/reduce conflict.
 */
mysql_while_cond :
					{
						int			endtok;

						$$ = read_sql_construct(K_LOOP, K_DO, 0,
												"LOOP or DO",
												RAW_PARSE_PLPGSQL_EXPR,
												true, true, NULL, &endtok);
						plmysql_push_back_token(endtok);
					}
				;

stmt_while		: opt_loop_label K_WHILE mysql_while_cond K_LOOP proc_sect K_END K_LOOP opt_label ';'
					{
						PLMySQL_stmt_while *new;

						new = palloc0(sizeof(PLMySQL_stmt_while));
						new->cmd_type = PLMYSQL_STMT_WHILE;
						new->lineno   = plmysql_location_to_lineno(@2);
						new->stmtid	  = ++plmysql_curr_compile->nstatements;
						new->label	  = $1;
						new->cond	  = $3;
						new->body	  = $5;

						check_labels($1, $8, @8);
						plmysql_ns_pop();

						$$ = (PLMySQL_stmt *)new;
					}
				| opt_loop_label K_WHILE mysql_while_cond K_DO proc_sect K_END K_WHILE opt_label ';'
					{
						PLMySQL_stmt_while *new;

						/* MySQL form: "WHILE cond DO stmts END WHILE [label]" */
						new = palloc0(sizeof(PLMySQL_stmt_while));
						new->cmd_type = PLMYSQL_STMT_WHILE;
						new->lineno   = plmysql_location_to_lineno(@2);
						new->stmtid	  = ++plmysql_curr_compile->nstatements;
						new->label	  = $1;
						new->cond	  = $3;
						new->body	  = $5;

						check_labels($1, $8, @8);
						plmysql_ns_pop();

						$$ = (PLMySQL_stmt *)new;
					}
				;

/*
 * MySQL: "REPEAT stmts UNTIL cond END REPEAT [label];"
 *
 * Lowers to a LOOP whose body is the statements followed by a conditional
 * EXIT: the body runs once, the UNTIL condition is evaluated, and the loop is
 * left when it is true.  (The UNTIL condition is read as raw text up to the
 * END keyword, so a condition containing a bare END -- i.e. a CASE expression
 * -- is not supported; MySQL's own grammar resolves that with its full
 * expression parser, which we deliberately do not model here.)
 */
stmt_repeat		: opt_loop_label K_REPEAT proc_sect K_UNTIL expr_until_end K_REPEAT opt_label ';'
					{
						PLMySQL_stmt_loop	*new;
						PLMySQL_stmt_exit	*xnew;

						xnew = palloc0(sizeof(PLMySQL_stmt_exit));
						xnew->cmd_type = PLMYSQL_STMT_EXIT;
						xnew->stmtid   = ++plmysql_curr_compile->nstatements;
						xnew->lineno   = plmysql_location_to_lineno(@5);
						xnew->is_exit  = true;
						xnew->label    = NULL;
						xnew->cond     = $5;

						new = palloc0(sizeof(PLMySQL_stmt_loop));
						new->cmd_type = PLMYSQL_STMT_LOOP;
						new->lineno   = plmysql_location_to_lineno(@2);
						new->stmtid   = ++plmysql_curr_compile->nstatements;
						new->label	  = $1;
						new->body	  = lappend($3, (PLMySQL_stmt *) xnew);

						check_labels($1, $7, @7);
						plmysql_ns_pop();

						$$ = (PLMySQL_stmt *)new;
					}
				;

expr_until_end	:
					{ $$ = read_sql_expression(K_END, "END"); }
				;

/*
 * MySQL: "LEAVE label;" leaves the block or loop carrying that label.
 */
stmt_leave		: K_LEAVE any_identifier ';'
					{
						PLMySQL_stmt_exit *new;
						PLMySQL_nsitem    *label;

						label = plmysql_ns_lookup_label(plmysql_ns_top(), $2);
						if (label == NULL)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("there is no label \"%s\" "
											"attached to any block or loop enclosing this statement",
											$2),
									 parser_errposition(@2)));

						new = palloc0(sizeof(PLMySQL_stmt_exit));
						new->cmd_type = PLMYSQL_STMT_EXIT;
						new->stmtid	  = ++plmysql_curr_compile->nstatements;
						new->is_exit  = true;
						new->lineno	  = plmysql_location_to_lineno(@1);
						new->label	  = $2;
						new->cond	  = NULL;

						$$ = (PLMySQL_stmt *)new;
					}
				;

/*
 * MySQL: "ITERATE label;" restarts the loop carrying that label.  Blocks are
 * not restartable, so only loop labels are legal here (same rule as
 * plpgsql's CONTINUE).
 */
stmt_iterate	: K_ITERATE any_identifier ';'
					{
						PLMySQL_stmt_exit *new;
						PLMySQL_nsitem    *label;

						label = plmysql_ns_lookup_label(plmysql_ns_top(), $2);
						if (label == NULL)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("there is no label \"%s\" "
											"attached to any block or loop enclosing this statement",
											$2),
									 parser_errposition(@2)));
						if (label->itemno != PLMYSQL_LABEL_LOOP)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("block label \"%s\" cannot be used in ITERATE",
											$2),
									 parser_errposition(@2)));

						new = palloc0(sizeof(PLMySQL_stmt_exit));
						new->cmd_type = PLMYSQL_STMT_EXIT;
						new->stmtid	  = ++plmysql_curr_compile->nstatements;
						new->is_exit  = false;
						new->lineno	  = plmysql_location_to_lineno(@1);
						new->label	  = $2;
						new->cond	  = NULL;

						$$ = (PLMySQL_stmt *)new;
					}
				;

stmt_for		: opt_loop_label K_FOR for_control loop_body
					{
						/* This runs after we've scanned the loop body */
						if ($3->cmd_type == PLMYSQL_STMT_FORI)
						{
							PLMySQL_stmt_fori		*new;

							new = (PLMySQL_stmt_fori *) $3;
							new->lineno   = plmysql_location_to_lineno(@2);
							new->label	  = $1;
							new->body	  = $4.stmts;
							$$ = (PLMySQL_stmt *) new;
						}
						else
						{
							PLMySQL_stmt_forq		*new;

							Assert($3->cmd_type == PLMYSQL_STMT_FORS ||
								   $3->cmd_type == PLMYSQL_STMT_FORC ||
								   $3->cmd_type == PLMYSQL_STMT_DYNFORS);
							/* forq is the common supertype of all three */
							new = (PLMySQL_stmt_forq *) $3;
							new->lineno   = plmysql_location_to_lineno(@2);
							new->label	  = $1;
							new->body	  = $4.stmts;
							$$ = (PLMySQL_stmt *) new;
						}

						check_labels($1, $4.end_label, $4.end_label_location);
						/* close namespace started in opt_loop_label */
						plmysql_ns_pop();
					}
				;

for_control		: for_variable K_IN
					{
						int			tok = yylex();
						int			tokloc = yylloc;

						if (tok == K_EXECUTE)
						{
							/* EXECUTE means it's a dynamic FOR loop */
							PLMySQL_stmt_dynfors	*new;
							PLMySQL_expr			*expr;
							int						term;

							expr = read_sql_expression2(K_LOOP, K_USING,
														"LOOP or USING",
														&term);

							new = palloc0(sizeof(PLMySQL_stmt_dynfors));
							new->cmd_type = PLMYSQL_STMT_DYNFORS;
							new->stmtid	  = ++plmysql_curr_compile->nstatements;
							if ($1.row)
							{
								new->var = (PLMySQL_variable *) $1.row;
								check_assignable($1.row, @1);
							}
							else if ($1.scalar)
							{
								/* convert single scalar to list */
								new->var = (PLMySQL_variable *)
									make_scalar_list1($1.name, $1.scalar,
													  $1.lineno, @1);
								/* make_scalar_list1 did check_assignable */
							}
							else
							{
								ereport(ERROR,
										(errcode(ERRCODE_DATATYPE_MISMATCH),
										 errmsg("loop variable of loop over rows must be a record variable or list of scalar variables"),
										 parser_errposition(@1)));
							}
							new->query = expr;

							if (term == K_USING)
							{
								do
								{
									expr = read_sql_expression2(',', K_LOOP,
																", or LOOP",
																&term);
									new->params = lappend(new->params, expr);
								} while (term == ',');
							}

							$$ = (PLMySQL_stmt *) new;
						}
						else if (tok == T_DATUM &&
								 yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_VAR &&
								 ((PLMySQL_var *) yylval.wdatum.datum)->datatype->typoid == REFCURSOROID)
						{
							/* It's FOR var IN cursor */
							PLMySQL_stmt_forc	*new;
							PLMySQL_var			*cursor = (PLMySQL_var *) yylval.wdatum.datum;

							new = (PLMySQL_stmt_forc *) palloc0(sizeof(PLMySQL_stmt_forc));
							new->cmd_type = PLMYSQL_STMT_FORC;
							new->stmtid = ++plmysql_curr_compile->nstatements;
							new->curvar = cursor->dno;

							/* Should have had a single variable name */
							if ($1.scalar && $1.row)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("cursor FOR loop must have only one target variable"),
										 parser_errposition(@1)));

							/* can't use an unbound cursor this way */
							if (cursor->cursor_explicit_expr == NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("cursor FOR loop must use a bound cursor variable"),
										 parser_errposition(tokloc)));

							/* collect cursor's parameters if any */
							new->argquery = read_cursor_args(cursor,
															 K_LOOP);

							/* create loop's private RECORD variable */
							new->var = (PLMySQL_variable *)
								plmysql_build_record($1.name,
													 $1.lineno,
													 NULL,
													 RECORDOID,
													 true);

							$$ = (PLMySQL_stmt *) new;
						}
						else
						{
							PLMySQL_expr	*expr1;
							int				expr1loc;
							bool			reverse = false;

							/*
							 * We have to distinguish between two
							 * alternatives: FOR var IN a .. b and FOR
							 * var IN query. Unfortunately this is
							 * tricky, since the query in the second
							 * form needn't start with a SELECT
							 * keyword.  We use the ugly hack of
							 * looking for two periods after the first
							 * token. We also check for the REVERSE
							 * keyword, which means it must be an
							 * integer loop.
							 */
							if (tok_is_keyword(tok, &yylval,
											   K_REVERSE, "reverse"))
								reverse = true;
							else
								plmysql_push_back_token(tok);

							/*
							 * Read tokens until we see either a ".."
							 * or a LOOP.  The text we read may be either
							 * an expression or a whole SQL statement, so
							 * we need to invoke read_sql_construct directly,
							 * and tell it not to check syntax yet.
							 */
							expr1 = read_sql_construct(DOT_DOT,
													   K_LOOP,
													   0,
													   "LOOP",
													   RAW_PARSE_DEFAULT,
													   true,
													   false,
													   &expr1loc,
													   &tok);

							if (tok == DOT_DOT)
							{
								/* Saw "..", so it must be an integer loop */
								PLMySQL_expr		*expr2;
								PLMySQL_expr		*expr_by;
								PLMySQL_var			*fvar;
								PLMySQL_stmt_fori	*new;

								/*
								 * Relabel first expression as an expression;
								 * then we can check its syntax.
								 */
								expr1->parseMode = RAW_PARSE_PLPGSQL_EXPR;
								check_sql_expr(expr1->query, expr1->parseMode,
											   expr1loc);

								/* Read and check the second one */
								expr2 = read_sql_expression2(K_LOOP, K_BY,
															 "LOOP",
															 &tok);

								/* Get the BY clause if any */
								if (tok == K_BY)
									expr_by = read_sql_expression(K_LOOP,
																  "LOOP");
								else
									expr_by = NULL;

								/* Should have had a single variable name */
								if ($1.scalar && $1.row)
									ereport(ERROR,
											(errcode(ERRCODE_SYNTAX_ERROR),
											 errmsg("integer FOR loop must have only one target variable"),
											 parser_errposition(@1)));

								/* create loop's private variable */
								fvar = (PLMySQL_var *)
									plmysql_build_variable($1.name,
														   $1.lineno,
														   plmysql_build_datatype(INT4OID,
																				  -1,
																				  InvalidOid,
																				  NULL),
														   true);

								new = palloc0(sizeof(PLMySQL_stmt_fori));
								new->cmd_type = PLMYSQL_STMT_FORI;
								new->stmtid	  = ++plmysql_curr_compile->nstatements;
								new->var	  = fvar;
								new->reverse  = reverse;
								new->lower	  = expr1;
								new->upper	  = expr2;
								new->step	  = expr_by;

								$$ = (PLMySQL_stmt *) new;
							}
							else
							{
								/*
								 * No "..", so it must be a query loop.
								 */
								PLMySQL_stmt_fors	*new;

								if (reverse)
									ereport(ERROR,
											(errcode(ERRCODE_SYNTAX_ERROR),
											 errmsg("cannot specify REVERSE in query FOR loop"),
											 parser_errposition(tokloc)));

								/* Check syntax as a regular query */
								check_sql_expr(expr1->query, expr1->parseMode,
											   expr1loc);

								new = palloc0(sizeof(PLMySQL_stmt_fors));
								new->cmd_type = PLMYSQL_STMT_FORS;
								new->stmtid = ++plmysql_curr_compile->nstatements;
								if ($1.row)
								{
									new->var = (PLMySQL_variable *) $1.row;
									check_assignable($1.row, @1);
								}
								else if ($1.scalar)
								{
									/* convert single scalar to list */
									new->var = (PLMySQL_variable *)
										make_scalar_list1($1.name, $1.scalar,
														  $1.lineno, @1);
									/* make_scalar_list1 did check_assignable */
								}
								else
								{
									ereport(ERROR,
											(errcode(ERRCODE_SYNTAX_ERROR),
											 errmsg("loop variable of loop over rows must be a record variable or list of scalar variables"),
											 parser_errposition(@1)));
								}

								new->query = expr1;
								$$ = (PLMySQL_stmt *) new;
							}
						}
					}
				;

/*
 * Processing the for_variable is tricky because we don't yet know if the
 * FOR is an integer FOR loop or a loop over query results.  In the former
 * case, the variable is just a name that we must instantiate as a loop
 * local variable, regardless of any other definition it might have.
 * Therefore, we always save the actual identifier into $$.name where it
 * can be used for that case.  We also save the outer-variable definition,
 * if any, because that's what we need for the loop-over-query case.  Note
 * that we must NOT apply check_assignable() or any other semantic check
 * until we know what's what.
 *
 * However, if we see a comma-separated list of names, we know that it
 * can't be an integer FOR loop and so it's OK to check the variables
 * immediately.  In particular, for T_WORD followed by comma, we should
 * complain that the name is not known rather than say it's a syntax error.
 * Note that the non-error result of this case sets *both* $$.scalar and
 * $$.row; see the for_control production.
 */
for_variable	: T_DATUM
					{
						$$.name = NameOfDatum(&($1));
						$$.lineno = plmysql_location_to_lineno(@1);
						if ($1.datum->dtype == PLMYSQL_DTYPE_ROW ||
							$1.datum->dtype == PLMYSQL_DTYPE_REC)
						{
							$$.scalar = NULL;
							$$.row = $1.datum;
						}
						else
						{
							int			tok;

							$$.scalar = $1.datum;
							$$.row = NULL;
							/* check for comma-separated list */
							tok = yylex();
							plmysql_push_back_token(tok);
							if (tok == ',')
								$$.row = (PLMySQL_datum *)
									read_into_scalar_list($$.name,
														  $$.scalar,
														  @1);
						}
					}
				| T_WORD
					{
						int			tok;

						$$.name = $1.ident;
						$$.lineno = plmysql_location_to_lineno(@1);
						$$.scalar = NULL;
						$$.row = NULL;
						/* check for comma-separated list */
						tok = yylex();
						plmysql_push_back_token(tok);
						if (tok == ',')
							word_is_not_variable(&($1), @1);
					}
				| T_CWORD
					{
						/* just to give a better message than "syntax error" */
						cword_is_not_variable(&($1), @1);
					}
				;

stmt_foreach_a	: opt_loop_label K_FOREACH for_variable foreach_slice K_IN K_ARRAY expr_until_loop loop_body
					{
						PLMySQL_stmt_foreach_a *new;

						new = palloc0(sizeof(PLMySQL_stmt_foreach_a));
						new->cmd_type = PLMYSQL_STMT_FOREACH_A;
						new->lineno = plmysql_location_to_lineno(@2);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						new->label = $1;
						new->slice = $4;
						new->expr = $7;
						new->body = $8.stmts;

						if ($3.row)
						{
							new->varno = $3.row->dno;
							check_assignable($3.row, @3);
						}
						else if ($3.scalar)
						{
							new->varno = $3.scalar->dno;
							check_assignable($3.scalar, @3);
						}
						else
						{
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("loop variable of FOREACH must be a known variable or list of variables"),
											 parser_errposition(@3)));
						}

						check_labels($1, $8.end_label, $8.end_label_location);
						plmysql_ns_pop();

						$$ = (PLMySQL_stmt *) new;
					}
				;

foreach_slice	:
					{
						$$ = 0;
					}
				| K_SLICE ICONST
					{
						$$ = $2;
					}
				;

stmt_exit		: exit_type opt_label opt_exitcond
					{
						PLMySQL_stmt_exit *new;

						new = palloc0(sizeof(PLMySQL_stmt_exit));
						new->cmd_type = PLMYSQL_STMT_EXIT;
						new->stmtid	  = ++plmysql_curr_compile->nstatements;
						new->is_exit  = $1;
						new->lineno	  = plmysql_location_to_lineno(@1);
						new->label	  = $2;
						new->cond	  = $3;

						if ($2)
						{
							/* We have a label, so verify it exists */
							PLMySQL_nsitem *label;

							label = plmysql_ns_lookup_label(plmysql_ns_top(), $2);
							if (label == NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("there is no label \"%s\" "
												"attached to any block or loop enclosing this statement",
												$2),
										 parser_errposition(@2)));
							/* CONTINUE only allows loop labels */
							if (label->itemno != PLMYSQL_LABEL_LOOP && !new->is_exit)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("block label \"%s\" cannot be used in CONTINUE",
												$2),
										 parser_errposition(@2)));
						}
						else
						{
							/*
							 * No label, so make sure there is some loop (an
							 * unlabeled EXIT does not match a block, so this
							 * is the same test for both EXIT and CONTINUE)
							 */
							if (plmysql_ns_find_nearest_loop(plmysql_ns_top()) == NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 new->is_exit ?
										 errmsg("EXIT cannot be used outside a loop, unless it has a label") :
										 errmsg("CONTINUE cannot be used outside a loop"),
										 parser_errposition(@1)));
						}

						$$ = (PLMySQL_stmt *)new;
					}
				;

exit_type		: K_EXIT
					{
						$$ = true;
					}
				| K_CONTINUE
					{
						$$ = false;
					}
				;

stmt_return		: K_RETURN
					{
						int	tok;

						tok = yylex();
						if (tok == 0)
							yyerror("unexpected end of function definition");

						if (tok_is_keyword(tok, &yylval,
										   K_NEXT, "next"))
						{
							$$ = make_return_next_stmt(@1);
						}
						else if (tok_is_keyword(tok, &yylval,
												K_QUERY, "query"))
						{
							$$ = make_return_query_stmt(@1);
						}
						else
						{
							plmysql_push_back_token(tok);
							$$ = make_return_stmt(@1);
						}
					}
				;

loop_body		: proc_sect K_END K_LOOP opt_label ';'
					{
						$$.stmts = $1;
						$$.end_label = $4;
						$$.end_label_location = @4;
					}
				;

/*
 * T_WORD+T_CWORD match any initial identifier that is not a known plmysql
 * variable.  (The composite case is probably a syntax error, but we'll let
 * the core parser decide that.)  Normally, we should assume that such a
 * word is a SQL statement keyword that isn't also a plmysql keyword.
 * However, if the next token is assignment or '[' or '.', it can't be a valid
 * SQL statement, and what we're probably looking at is an intended variable
 * assignment.  Give an appropriate complaint for that, instead of letting
 * the core parser throw an unhelpful "syntax error".
 */
stmt_execsql	: K_IMPORT
					{
						$$ = make_execsql_stmt(K_IMPORT, @1, NULL);
					}
				| K_INSERT
					{
						$$ = make_execsql_stmt(K_INSERT, @1, NULL);
					}
				| T_WORD
					{
						int			tok;

						tok = yylex();
						plmysql_push_back_token(tok);
						if (tok == '=' || tok == COLON_EQUALS ||
							tok == '[' || tok == '.')
							word_is_not_variable(&($1), @1);
						$$ = make_execsql_stmt(T_WORD, @1, &($1));
					}
				| T_CWORD
					{
						int			tok;

						tok = yylex();
						plmysql_push_back_token(tok);
						if (tok == '=' || tok == COLON_EQUALS ||
							tok == '[' || tok == '.')
							cword_is_not_variable(&($1), @1);
						$$ = make_execsql_stmt(T_CWORD, @1, NULL);
					}
				;

/*
 * MySQL's EXECUTE is "EXECUTE stmt_name [USING @var [, @var ...]];" -- a
 * previously PREPAREd statement run by name.  That has nothing in common
 * with plpgsql's own dynamic-SQL "EXECUTE expr [INTO ...] [USING ...]"
 * statement this nonterminal was cloned from (this production used to build
 * that; see git history), and MySQL SQL/PSM has no equivalent of the
 * latter.  Rather than teach this grammar MySQL's EXECUTE shape -- which
 * would just have to turn around and reassemble "EXECUTE name USING ..." as
 * a string to hand to SPI anyway, since running a prepared statement by name
 * is not something this grammar can do on its own -- the whole statement is
 * captured and executed verbatim, exactly like a generic passthrough SQL
 * statement (stmt_execsql's make_execsql_stmt): under the MySQL protocol
 * session that every plmysql routine runs in, SPI parses it with the very
 * same grammar that already runs a top-level "EXECUTE name USING ...;", so
 * the existing PREPARE/EXECUTE/DEALLOCATE PREPARE machinery (mys_prepare.c)
 * runs it unchanged, INTO clause and all -- MySQL's EXECUTE has no INTO
 * clause; a result set it produces is delivered exactly like a bare SELECT
 * (see make_execsql_stmt's is_select, and pl_exec.c's exec_stmt_execsql()).
 *
 * This leaves PLMySQL_stmt_dynexecute and exec_stmt_dynexecute() otherwise
 * intact but unreachable from this grammar; removing that dead code is a
 * separate, larger cleanup than this fix.
 */
stmt_dynexecute : K_EXECUTE
					{
						$$ = make_execsql_stmt(K_EXECUTE, @1, NULL);
					}
				;


stmt_open		: K_OPEN cursor_variable
					{
						PLMySQL_stmt_open *new;
						int				  tok;

						new = palloc0(sizeof(PLMySQL_stmt_open));
						new->cmd_type = PLMYSQL_STMT_OPEN;
						new->lineno = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						new->curvar = $2->dno;
						new->cursor_options = CURSOR_OPT_FAST_PLAN;

						if ($2->cursor_explicit_expr == NULL)
						{
							/* be nice if we could use opt_scrollable here */
							tok = yylex();
							if (tok_is_keyword(tok, &yylval,
											   K_NO, "no"))
							{
								tok = yylex();
								if (tok_is_keyword(tok, &yylval,
												   K_SCROLL, "scroll"))
								{
									new->cursor_options |= CURSOR_OPT_NO_SCROLL;
									tok = yylex();
								}
							}
							else if (tok_is_keyword(tok, &yylval,
													K_SCROLL, "scroll"))
							{
								new->cursor_options |= CURSOR_OPT_SCROLL;
								tok = yylex();
							}

							if (tok != K_FOR)
								yyerror("syntax error, expected \"FOR\"");

							tok = yylex();
							if (tok == K_EXECUTE)
							{
								int		endtoken;

								new->dynquery =
									read_sql_expression2(K_USING, ';',
														 "USING or ;",
														 &endtoken);

								/* If we found "USING", collect argument(s) */
								if (endtoken == K_USING)
								{
									PLMySQL_expr *expr;

									do
									{
										expr = read_sql_expression2(',', ';',
																	", or ;",
																	&endtoken);
										new->params = lappend(new->params,
															  expr);
									} while (endtoken == ',');
								}
							}
							else
							{
								plmysql_push_back_token(tok);
								new->query = read_sql_stmt();
							}
						}
						else
						{
							/* predefined cursor query, so read args */
							new->argquery = read_cursor_args($2, ';');
						}

						$$ = (PLMySQL_stmt *)new;
					}
				;

stmt_fetch		: K_FETCH opt_fetch_direction cursor_variable K_INTO
					{
						PLMySQL_stmt_fetch *fetch = $2;
						PLMySQL_variable *target;

						/* We have already parsed everything through the INTO keyword */
						read_into_target(&target, NULL);

						if (yylex() != ';')
							yyerror("syntax error");

						/*
						 * We don't allow multiple rows in PL/MySQL's FETCH
						 * statement, only in MOVE.
						 */
						if (fetch->returns_multiple_rows)
							ereport(ERROR,
									(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
									 errmsg("FETCH statement cannot return multiple rows"),
									 parser_errposition(@1)));

						fetch->lineno = plmysql_location_to_lineno(@1);
						fetch->target	= target;
						fetch->curvar	= $3->dno;
						fetch->is_move	= false;

						$$ = (PLMySQL_stmt *)fetch;
					}
				;

stmt_move		: K_MOVE opt_fetch_direction cursor_variable ';'
					{
						PLMySQL_stmt_fetch *fetch = $2;

						fetch->lineno = plmysql_location_to_lineno(@1);
						fetch->curvar	= $3->dno;
						fetch->is_move	= true;

						$$ = (PLMySQL_stmt *)fetch;
					}
				;

opt_fetch_direction	:
					{
						$$ = read_fetch_direction();
					}
				;

stmt_close		: K_CLOSE cursor_variable ';'
					{
						PLMySQL_stmt_close *new;

						new = palloc(sizeof(PLMySQL_stmt_close));
						new->cmd_type = PLMYSQL_STMT_CLOSE;
						new->lineno = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						new->curvar = $2->dno;

						$$ = (PLMySQL_stmt *)new;
					}
				;

stmt_null		: K_NULL ';'
					{
						/* We do not bother building a node for NULL */
						$$ = NULL;
					}
				;

stmt_commit		: K_COMMIT opt_transaction_chain ';'
					{
						PLMySQL_stmt_commit *new;

						new = palloc(sizeof(PLMySQL_stmt_commit));
						new->cmd_type = PLMYSQL_STMT_COMMIT;
						new->lineno = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						new->chain = $2;

						$$ = (PLMySQL_stmt *)new;
					}
				;

stmt_rollback	: K_ROLLBACK opt_transaction_chain ';'
					{
						PLMySQL_stmt_rollback *new;

						new = palloc(sizeof(PLMySQL_stmt_rollback));
						new->cmd_type = PLMYSQL_STMT_ROLLBACK;
						new->lineno = plmysql_location_to_lineno(@1);
						new->stmtid = ++plmysql_curr_compile->nstatements;
						new->chain = $2;

						$$ = (PLMySQL_stmt *)new;
					}
				;

opt_transaction_chain:
			K_AND K_CHAIN			{ $$ = true; }
			| K_AND K_NO K_CHAIN	{ $$ = false; }
			| /* EMPTY */			{ $$ = false; }
				;


cursor_variable	: T_DATUM
					{
						/*
						 * In principle we should support a cursor_variable
						 * that is an array element, but for now we don't, so
						 * just throw an error if next token is '['.
						 */
						if ($1.datum->dtype != PLMYSQL_DTYPE_VAR ||
							plmysql_peek() == '[')
							ereport(ERROR,
									(errcode(ERRCODE_DATATYPE_MISMATCH),
									 errmsg("cursor variable must be a simple variable"),
									 parser_errposition(@1)));

						if (((PLMySQL_var *) $1.datum)->datatype->typoid != REFCURSOROID)
							ereport(ERROR,
									(errcode(ERRCODE_DATATYPE_MISMATCH),
									 errmsg("variable \"%s\" must be of type cursor or refcursor",
											((PLMySQL_var *) $1.datum)->refname),
									 parser_errposition(@1)));
						$$ = (PLMySQL_var *) $1.datum;
					}
				| T_WORD
					{
						/* just to give a better message than "syntax error" */
						word_is_not_variable(&($1), @1);
					}
				| T_CWORD
					{
						/* just to give a better message than "syntax error" */
						cword_is_not_variable(&($1), @1);
					}
				;

exception_sect	:
					{ $$ = NULL; }
				| K_EXCEPTION
					{
						/*
						 * We use a mid-rule action to add these
						 * special variables to the namespace before
						 * parsing the WHEN clauses themselves.  The
						 * scope of the names extends to the end of the
						 * current block.
						 */
						int			lineno = plmysql_location_to_lineno(@1);
						PLMySQL_exception_block *new = palloc(sizeof(PLMySQL_exception_block));
						PLMySQL_variable *var;

						var = plmysql_build_variable("sqlstate", lineno,
													 plmysql_build_datatype(TEXTOID,
																			-1,
																			plmysql_curr_compile->fn_input_collation,
																			NULL),
													 true);
						var->isconst = true;
						new->sqlstate_varno = var->dno;

						var = plmysql_build_variable("sqlerrm", lineno,
													 plmysql_build_datatype(TEXTOID,
																			-1,
																			plmysql_curr_compile->fn_input_collation,
																			NULL),
													 true);
						var->isconst = true;
						new->sqlerrm_varno = var->dno;

						$<exception_block>$ = new;
					}
					proc_exceptions
					{
						PLMySQL_exception_block *new = $<exception_block>2;
						new->exc_list = $3;

						$$ = new;
					}
				;

proc_exceptions	: proc_exceptions proc_exception
						{
							$$ = lappend($1, $2);
						}
				| proc_exception
						{
							$$ = list_make1($1);
						}
				;

proc_exception	: K_WHEN proc_conditions K_THEN proc_sect
					{
						PLMySQL_exception *new;

						new = palloc0(sizeof(PLMySQL_exception));
						new->lineno = plmysql_location_to_lineno(@1);
						new->conditions = $2;
						new->action = $4;

						$$ = new;
					}
				;

proc_conditions	: proc_conditions K_OR proc_condition
						{
							PLMySQL_condition	*old;

							for (old = $1; old->next != NULL; old = old->next)
								/* skip */ ;
							old->next = $3;
							$$ = $1;
						}
				| proc_condition
						{
							$$ = $1;
						}
				;

proc_condition	: any_identifier
						{
							if (strcmp($1, "sqlstate") != 0)
							{
								$$ = plmysql_parse_err_condition($1);
							}
							else
							{
								PLMySQL_condition *new;
								char   *sqlstatestr;

								/* next token should be a string literal */
								if (yylex() != SCONST)
									yyerror("syntax error");
								sqlstatestr = yylval.str;

								if (strlen(sqlstatestr) != 5)
									yyerror("invalid SQLSTATE code");
								if (strspn(sqlstatestr, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") != 5)
									yyerror("invalid SQLSTATE code");

								new = palloc(sizeof(PLMySQL_condition));
								new->sqlerrstate =
									MAKE_SQLSTATE(sqlstatestr[0],
												  sqlstatestr[1],
												  sqlstatestr[2],
												  sqlstatestr[3],
												  sqlstatestr[4]);
								new->condname = sqlstatestr;
								new->next = NULL;

								$$ = new;
							}
						}
				;

expr_until_semi :
					{ $$ = read_sql_expression(';', ";"); }
				;

expr_until_then :
					{ $$ = read_sql_expression(K_THEN, "THEN"); }
				;

expr_until_loop :
					{ $$ = read_sql_expression(K_LOOP, "LOOP"); }
				;

opt_block_label	:
					{
						plmysql_ns_push(NULL, PLMYSQL_LABEL_BLOCK);
						$$ = NULL;
					}
				| LESS_LESS any_identifier GREATER_GREATER
					{
						plmysql_ns_push($2, PLMYSQL_LABEL_BLOCK);
						$$ = $2;
					}
				;

opt_loop_label	:
					{
						plmysql_ns_push(NULL, PLMYSQL_LABEL_LOOP);
						$$ = NULL;
					}
				| LESS_LESS any_identifier GREATER_GREATER
					{
						plmysql_ns_push($2, PLMYSQL_LABEL_LOOP);
						$$ = $2;
					}
				;

opt_label	:
					{
						$$ = NULL;
					}
				| any_identifier
					{
						/* label validity will be checked by outer production */
						$$ = $1;
					}
				;

opt_exitcond	: ';'
					{ $$ = NULL; }
				| K_WHEN expr_until_semi
					{ $$ = $2; }
				;

/*
 * need to allow DATUM because scanner will have tried to resolve as variable
 */
any_identifier	: T_WORD
					{
						$$ = $1.ident;
					}
				| unreserved_keyword
					{
						$$ = pstrdup($1);
					}
				| T_DATUM
					{
						if ($1.ident == NULL) /* composite name not OK */
							yyerror("syntax error");
						$$ = $1.ident;
					}
				;

unreserved_keyword	:
				K_ABSOLUTE
				| K_AND
				| K_ARRAY
				| K_BACKWARD
				| K_CALL
				| K_CHAIN
				| K_CLOSE
				| K_COLLATE
				| K_COLUMN
				| K_COLUMN_NAME
				| K_COMMIT
				| K_CONSTANT
				| K_CONSTRAINT
				| K_CONSTRAINT_NAME
				| K_CURRENT
				| K_CURSOR
				| K_DATATYPE
				| K_DEBUG
				| K_DEFAULT
				| K_DETAIL
				| K_DIAGNOSTICS
				| K_DO
				| K_DUMP
				| K_ELSIF
				| K_ERRCODE
				| K_ERROR
				| K_EXCEPTION
				| K_FETCH
				| K_FIRST
				| K_FORWARD
				| K_GET
				| K_HINT
				| K_IMPORT
				| K_INFO
				| K_INSERT
				| K_IS
				| K_LAST
				| K_LOG
				| K_MESSAGE
				| K_MESSAGE_TEXT
				| K_MOVE
				| K_NEXT
				| K_NO
				| K_NOTICE
				| K_OPEN
				| K_OPTION
				| K_PG_CONTEXT
				| K_PG_DATATYPE_NAME
				| K_PG_EXCEPTION_CONTEXT
				| K_PG_EXCEPTION_DETAIL
				| K_PG_EXCEPTION_HINT
				| K_PRINT_STRICT_PARAMS
				| K_PRIOR
				| K_QUERY
				| K_RELATIVE
				| K_RETURN
				| K_RETURNED_SQLSTATE
				| K_REVERSE
				| K_ROLLBACK
				| K_ROW_COUNT
				| K_ROWTYPE
				| K_SCHEMA
				| K_SCHEMA_NAME
				| K_SCROLL
				| K_SLICE
				| K_STACKED
				| K_TABLE
				| K_TABLE_NAME
				| K_TYPE
				| K_USE_COLUMN
				| K_USE_VARIABLE
				| K_VARIABLE_CONFLICT
				| K_WARNING
				;

%%

/*
 * Check whether a token represents an "unreserved keyword".
 * We have various places where we want to recognize a keyword in preference
 * to a variable name, but not reserve that keyword in other contexts.
 * Hence, this kluge.
 */
static bool
tok_is_keyword(int token, union YYSTYPE *lval,
			   int kw_token, const char *kw_str)
{
	if (token == kw_token)
	{
		/* Normal case, was recognized by scanner (no conflicting variable) */
		return true;
	}
	else if (token == T_DATUM)
	{
		/*
		 * It's a variable, so recheck the string name.  Note we will not
		 * match composite names (hence an unreserved word followed by "."
		 * will not be recognized).
		 */
		if (!lval->wdatum.quoted && lval->wdatum.ident != NULL &&
			strcmp(lval->wdatum.ident, kw_str) == 0)
			return true;
	}
	return false;				/* not the keyword */
}

/*
 * Convenience routine to complain when we expected T_DATUM and got T_WORD,
 * ie, unrecognized variable.
 */
static void
word_is_not_variable(PLword *word, int location)
{
	ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			 errmsg("\"%s\" is not a known variable",
					word->ident),
			 parser_errposition(location)));
}

/* Same, for a CWORD */
static void
cword_is_not_variable(PLcword *cword, int location)
{
	ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			 errmsg("\"%s\" is not a known variable",
					NameListToString(cword->idents)),
			 parser_errposition(location)));
}

/*
 * Convenience routine to complain when we expected T_DATUM and got
 * something else.  "tok" must be the current token, since we also
 * look at yylval and yylloc.
 */
static void
current_token_is_not_variable(int tok)
{
	if (tok == T_WORD)
		word_is_not_variable(&(yylval.word), yylloc);
	else if (tok == T_CWORD)
		cword_is_not_variable(&(yylval.cword), yylloc);
	else
		yyerror("syntax error");
}

/* Convenience routine to read an expression with one possible terminator */
static PLMySQL_expr *
read_sql_expression(int until, const char *expected)
{
	return read_sql_construct(until, 0, 0, expected,
							  RAW_PARSE_PLPGSQL_EXPR,
							  true, true, NULL, NULL);
}

/* Convenience routine to read an expression with two possible terminators */
static PLMySQL_expr *
read_sql_expression2(int until, int until2, const char *expected,
					 int *endtoken)
{
	return read_sql_construct(until, until2, 0, expected,
							  RAW_PARSE_PLPGSQL_EXPR,
							  true, true, NULL, endtoken);
}

/* Convenience routine to read a SQL statement that must end with ';' */
static PLMySQL_expr *
read_sql_stmt(void)
{
	return read_sql_construct(';', 0, 0, ";",
							  RAW_PARSE_DEFAULT,
							  false, true, NULL, NULL);
}

/*
 * Read a SQL construct and build a PLMySQL_expr for it.
 *
 * until:		token code for expected terminator
 * until2:		token code for alternate terminator (pass 0 if none)
 * until3:		token code for another alternate terminator (pass 0 if none)
 * expected:	text to use in complaining that terminator was not found
 * parsemode:	raw_parser() mode to use
 * isexpression: whether to say we're reading an "expression" or a "statement"
 * valid_sql:   whether to check the syntax of the expr
 * startloc:	if not NULL, location of first token is stored at *startloc
 * endtoken:	if not NULL, ending token is stored at *endtoken
 *				(this is only interesting if until2 or until3 isn't zero)
 */
static PLMySQL_expr *
read_sql_construct(int until,
				   int until2,
				   int until3,
				   const char *expected,
				   RawParseMode parsemode,
				   bool isexpression,
				   bool valid_sql,
				   int *startloc,
				   int *endtoken)
{
	int					tok;
	StringInfoData		ds;
	IdentifierLookup	save_IdentifierLookup;
	int					startlocation = -1;
	int					endlocation = -1;
	int					parenlevel = 0;
	PLMySQL_expr		*expr;

	initStringInfo(&ds);

	/* special lookup mode for identifiers within the SQL text */
	save_IdentifierLookup = plmysql_IdentifierLookup;
	plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_EXPR;

	for (;;)
	{
		tok = yylex();
		if (startlocation < 0)			/* remember loc of first token */
			startlocation = yylloc;
		if (tok == until && parenlevel == 0)
			break;
		if (tok == until2 && parenlevel == 0)
			break;
		if (tok == until3 && parenlevel == 0)
			break;
		if (tok == '(' || tok == '[')
			parenlevel++;
		else if (tok == ')' || tok == ']')
		{
			parenlevel--;
			if (parenlevel < 0)
				yyerror("mismatched parentheses");
		}
		/*
		 * End of function definition is an error, and we don't expect to
		 * hit a semicolon either (unless it's the until symbol, in which
		 * case we should have fallen out above).
		 */
		if (tok == 0 || tok == ';')
		{
			if (parenlevel != 0)
				yyerror("mismatched parentheses");
			if (isexpression)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("missing \"%s\" at end of SQL expression",
								expected),
						 parser_errposition(yylloc)));
			else
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("missing \"%s\" at end of SQL statement",
								expected),
						 parser_errposition(yylloc)));
		}
		/* Remember end+1 location of last accepted token */
		endlocation = yylloc + plmysql_token_length();
	}

	plmysql_IdentifierLookup = save_IdentifierLookup;

	if (startloc)
		*startloc = startlocation;
	if (endtoken)
		*endtoken = tok;

	/* give helpful complaint about empty input */
	if (startlocation >= endlocation)
	{
		if (isexpression)
			yyerror("missing expression");
		else
			yyerror("missing SQL statement");
	}

	/*
	 * We save only the text from startlocation to endlocation-1.  This
	 * suppresses the "until" token as well as any whitespace or comments
	 * following the last accepted token.  (We used to strip such trailing
	 * whitespace by hand, but that causes problems if there's a "-- comment"
	 * in front of said whitespace.)
	 */
	plmysql_append_source_text(&ds, startlocation, endlocation);

	expr = palloc0(sizeof(PLMySQL_expr));
	expr->query			= pstrdup(ds.data);
	expr->parseMode		= parsemode;
	expr->plan			= NULL;
	expr->paramnos		= NULL;
	expr->target_param	= -1;
	expr->ns			= plmysql_ns_top();
	pfree(ds.data);

	if (valid_sql)
		check_sql_expr(expr->query, expr->parseMode, startlocation);

	return expr;
}

static PLMySQL_type *
read_datatype(int tok)
{
	StringInfoData		ds;
	char			   *type_name;
	int					startlocation;
	PLMySQL_type		*result;
	int					parenlevel = 0;

	/* Should only be called while parsing DECLARE sections */
	Assert(plmysql_IdentifierLookup == IDENTIFIER_LOOKUP_DECLARE);

	/* Often there will be a lookahead token, but if not, get one */
	if (tok == YYEMPTY)
		tok = yylex();

	startlocation = yylloc;

	/*
	 * If we have a simple or composite identifier, check for %TYPE
	 * and %ROWTYPE constructs.
	 */
	if (tok == T_WORD)
	{
		char   *dtname = yylval.word.ident;

		tok = yylex();
		if (tok == '%')
		{
			tok = yylex();
			if (tok_is_keyword(tok, &yylval,
							   K_TYPE, "type"))
			{
				result = plmysql_parse_wordtype(dtname);
				if (result)
					return result;
			}
			else if (tok_is_keyword(tok, &yylval,
									K_ROWTYPE, "rowtype"))
			{
				result = plmysql_parse_wordrowtype(dtname);
				if (result)
					return result;
			}
		}
	}
	else if (plmysql_token_is_unreserved_keyword(tok))
	{
		char   *dtname = pstrdup(yylval.keyword);

		tok = yylex();
		if (tok == '%')
		{
			tok = yylex();
			if (tok_is_keyword(tok, &yylval,
							   K_TYPE, "type"))
			{
				result = plmysql_parse_wordtype(dtname);
				if (result)
					return result;
			}
			else if (tok_is_keyword(tok, &yylval,
									K_ROWTYPE, "rowtype"))
			{
				result = plmysql_parse_wordrowtype(dtname);
				if (result)
					return result;
			}
		}
	}
	else if (tok == T_CWORD)
	{
		List   *dtnames = yylval.cword.idents;

		tok = yylex();
		if (tok == '%')
		{
			tok = yylex();
			if (tok_is_keyword(tok, &yylval,
							   K_TYPE, "type"))
			{
				result = plmysql_parse_cwordtype(dtnames);
				if (result)
					return result;
			}
			else if (tok_is_keyword(tok, &yylval,
									K_ROWTYPE, "rowtype"))
			{
				result = plmysql_parse_cwordrowtype(dtnames);
				if (result)
					return result;
			}
		}
	}

	while (tok != ';')
	{
		if (tok == 0)
		{
			if (parenlevel != 0)
				yyerror("mismatched parentheses");
			else
				yyerror("incomplete data type declaration");
		}
		/* Possible followers for datatype in a declaration */
		if (tok == K_COLLATE || tok == K_NOT ||
			tok == '=' || tok == COLON_EQUALS || tok == K_DEFAULT)
			break;
		/* Possible followers for datatype in a cursor_arg list */
		if ((tok == ',' || tok == ')') && parenlevel == 0)
			break;
		if (tok == '(')
			parenlevel++;
		else if (tok == ')')
			parenlevel--;

		tok = yylex();
	}

	/* set up ds to contain complete typename text */
	initStringInfo(&ds);
	plmysql_append_source_text(&ds, startlocation, yylloc);
	type_name = ds.data;

	if (type_name[0] == '\0')
		yyerror("missing data type declaration");

	result = parse_datatype(type_name, startlocation);

	pfree(ds.data);

	plmysql_push_back_token(tok);

	return result;
}

/*
 * Read a generic SQL statement.  We have already read its first token;
 * firsttoken is that token's code and location its starting location.
 * If firsttoken == T_WORD, pass its yylval value as "word", else pass NULL.
 */
static PLMySQL_stmt *
make_execsql_stmt(int firsttoken, int location, PLword *word)
{
	StringInfoData		ds;
	IdentifierLookup	save_IdentifierLookup;
	PLMySQL_stmt_execsql *execsql;
	PLMySQL_expr		*expr;
	PLMySQL_variable	*target = NULL;
	int					tok;
	int					prev_tok;
	bool				have_into = false;
	bool				have_strict = false;
	int					into_start_loc = -1;
	int					into_end_loc = -1;
	int			paren_depth = 0;
	int			begin_depth = 0;
	bool		in_routine_definition = false;
	int			token_count = 0;
	char		tokens[4];		/* records the first few tokens */

	initStringInfo(&ds);

	memset(tokens, 0, sizeof(tokens));

	mysql_check_dynamic_sql_context(firsttoken, word, location);

	/* special lookup mode for identifiers within the SQL text */
	save_IdentifierLookup = plmysql_IdentifierLookup;
	plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_EXPR;

	/*
	 * Scan to the end of the SQL command.  Identify any INTO-variables
	 * clause lurking within it, and parse that via read_into_target().
	 *
	 * The end of the statement is defined by a semicolon ... except that
	 * semicolons within parentheses or BEGIN/END blocks don't terminate a
	 * statement.  We follow psql's lead in not recognizing BEGIN/END except
	 * after CREATE [OR REPLACE] {FUNCTION|PROCEDURE}.  END can also appear
	 * within a CASE construct, so we treat CASE/END like BEGIN/END.
	 *
	 * Because INTO is sometimes used in the main SQL grammar, we have to be
	 * careful not to take any such usage of INTO as a PL/MySQL INTO clause.
	 * There are currently three such cases:
	 *
	 * 1. SELECT ... INTO.  We don't care, we just override that with the
	 * PL/MySQL definition.
	 *
	 * 2. INSERT INTO.  This is relatively easy to recognize since the words
	 * must appear adjacently; but we can't assume INSERT starts the command,
	 * because it can appear in CREATE RULE or WITH.  Unfortunately, INSERT is
	 * *not* fully reserved, so that means there is a chance of a false match;
	 * but it's not very likely.
	 *
	 * 3. IMPORT FOREIGN SCHEMA ... INTO.  This is not allowed in CREATE RULE
	 * or WITH, so we just check for IMPORT as the command's first token.
	 * (If IMPORT FOREIGN SCHEMA returned data someone might wish to capture
	 * with an INTO-variables clause, we'd have to work much harder here.)
	 *
	 * Fortunately, INTO is a fully reserved word in the main grammar, so
	 * at least we need not worry about it appearing as an identifier.
	 *
	 * Any future additional uses of INTO in the main grammar will doubtless
	 * break this logic again ... beware!
	 */
	tok = firsttoken;
	if (tok == T_WORD && strcmp(word->ident, "create") == 0)
		tokens[token_count] = 'c';
	token_count++;

	for (;;)
	{
		prev_tok = tok;
		tok = yylex();
		if (have_into && into_end_loc < 0)
			into_end_loc = yylloc;		/* token after the INTO part */
		/* Detect CREATE [OR REPLACE] {FUNCTION|PROCEDURE} */
		if (tokens[0] == 'c' && token_count < sizeof(tokens))
		{
			if (tok == K_OR)
				tokens[token_count] = 'o';
			else if (tok == T_WORD &&
					 strcmp(yylval.word.ident, "replace") == 0)
				tokens[token_count] = 'r';
			else if (tok == T_WORD &&
					 strcmp(yylval.word.ident, "function") == 0)
				tokens[token_count] = 'f';
			else if (tok == T_WORD &&
					 strcmp(yylval.word.ident, "procedure") == 0)
				tokens[token_count] = 'f';	/* treat same as "function" */
			if (tokens[1] == 'f' ||
				(tokens[1] == 'o' && tokens[2] == 'r' && tokens[3] == 'f'))
				in_routine_definition = true;
			token_count++;
		}
		/* Track paren nesting (needed for CREATE RULE syntax) */
		if (tok == '(')
			paren_depth++;
		else if (tok == ')' && paren_depth > 0)
			paren_depth--;
		/* We need track BEGIN/END nesting only in a routine definition */
		if (in_routine_definition && paren_depth == 0)
		{
			if (tok == K_BEGIN || tok == K_CASE)
				begin_depth++;
			else if (tok == K_END && begin_depth > 0)
				begin_depth--;
		}
		/* Command-ending semicolon? */
		if (tok == ';' && paren_depth == 0 && begin_depth == 0)
			break;
		if (tok == 0)
			yyerror("unexpected end of function definition");
		if (tok == K_INTO)
		{
			if (prev_tok == K_INSERT)
				continue;		/* INSERT INTO is not an INTO-target */
			if (firsttoken == K_IMPORT)
				continue;		/* IMPORT ... INTO is not an INTO-target */
			if (have_into)
				yyerror("INTO specified more than once");
			have_into = true;
			into_start_loc = yylloc;
			plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;
			read_into_target(&target, &have_strict);
			plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_EXPR;
		}
	}

	plmysql_IdentifierLookup = save_IdentifierLookup;

	if (have_into)
	{
		/*
		 * Insert an appropriate number of spaces corresponding to the
		 * INTO text, so that locations within the redacted SQL statement
		 * still line up with those in the original source text.
		 */
		plmysql_append_source_text(&ds, location, into_start_loc);
		appendStringInfoSpaces(&ds, into_end_loc - into_start_loc);
		plmysql_append_source_text(&ds, into_end_loc, yylloc);
	}
	else
		plmysql_append_source_text(&ds, location, yylloc);

	/* trim any trailing whitespace, for neatness */
	while (ds.len > 0 && scanner_isspace(ds.data[ds.len - 1]))
		ds.data[--ds.len] = '\0';

	expr = palloc0(sizeof(PLMySQL_expr));
	expr->query			= pstrdup(ds.data);
	expr->parseMode		= RAW_PARSE_DEFAULT;
	expr->plan			= NULL;
	expr->paramnos		= NULL;
	expr->target_param	= -1;
	expr->ns			= plmysql_ns_top();
	pfree(ds.data);

	check_sql_expr(expr->query, expr->parseMode, location);

	execsql = palloc0(sizeof(PLMySQL_stmt_execsql));
	execsql->cmd_type = PLMYSQL_STMT_EXECSQL;
	execsql->is_select = (!have_into &&
						  ((firsttoken == T_WORD && word != NULL &&
							!word->quoted && word->ident != NULL &&
							pg_strcasecmp(word->ident, "select") == 0) ||
						   /*
							* MySQL's EXECUTE of a previously PREPAREd
							* statement (captured here too -- see
							* stmt_dynexecute) can just as well be a SELECT,
							* only known once SPI actually runs it; count it
							* as a possible result-set push for the same
							* reason a literal SELECT is counted, on the same
							* best-effort, straight-line basis (see the
							* comment on PLMySQL_execstate.resultsets_sent).
							*/
						   firsttoken == K_EXECUTE));
	if (execsql->is_select)
		plmysql_curr_compile->n_resultsets++;
	execsql->lineno  = plmysql_location_to_lineno(location);
	execsql->stmtid  = ++plmysql_curr_compile->nstatements;
	execsql->sqlstmt = expr;
	execsql->into	 = have_into;
	execsql->strict	 = have_strict;
	execsql->target	 = target;

	return (PLMySQL_stmt *) execsql;
}

/*
 * MySQL's named PREPARE/EXECUTE/DEALLOCATE statements are session-scoped.
 * They are valid in stored procedures, but MySQL 5.7 rejects them while a
 * stored function or trigger is being compiled (ER_STMT_NOT_ALLOWED_IN_SF_OR_TRG).
 * PREPARE and DEALLOCATE arrive here as ordinary words; EXECUTE has its own
 * grammar token, so recognize both paths before handing the statement to SPI.
 */
static void
mysql_check_dynamic_sql_context(int firsttoken, PLword *word, int location)
{
	bool		is_dynamic_sql = firsttoken == K_EXECUTE;

	if (firsttoken == T_WORD && word != NULL && !word->quoted &&
		word->ident != NULL &&
		(pg_strcasecmp(word->ident, "prepare") == 0 ||
		 pg_strcasecmp(word->ident, "deallocate") == 0))
		is_dynamic_sql = true;

	if (!is_dynamic_sql ||
		(plmysql_curr_compile->fn_prokind != PROKIND_FUNCTION &&
		 plmysql_curr_compile->fn_is_trigger == PLMYSQL_NOT_TRIGGER))
		return;

	mysSetPendingMySQLErrno(1336); /* ER_STMT_NOT_ALLOWED_IN_SF_OR_TRG */
	ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			 errmsg("Dynamic SQL is not allowed in stored function or trigger"),
			 parser_errposition(location)));
}


/*
 * Read FETCH or MOVE direction clause (everything through FROM/IN).
 */
static PLMySQL_stmt_fetch *
read_fetch_direction(void)
{
	PLMySQL_stmt_fetch *fetch;
	int			tok;
	bool		check_FROM = true;

	/*
	 * We create the PLMySQL_stmt_fetch struct here, but only fill in
	 * the fields arising from the optional direction clause
	 */
	fetch = (PLMySQL_stmt_fetch *) palloc0(sizeof(PLMySQL_stmt_fetch));
	fetch->cmd_type = PLMYSQL_STMT_FETCH;
	fetch->stmtid	= ++plmysql_curr_compile->nstatements;
	/* set direction defaults: */
	fetch->direction = FETCH_FORWARD;
	fetch->how_many  = 1;
	fetch->expr		 = NULL;
	fetch->returns_multiple_rows = false;

	tok = yylex();
	if (tok == 0)
		yyerror("unexpected end of function definition");

	if (tok_is_keyword(tok, &yylval,
					   K_NEXT, "next"))
	{
		/* use defaults */
	}
	else if (tok_is_keyword(tok, &yylval,
							K_PRIOR, "prior"))
	{
		fetch->direction = FETCH_BACKWARD;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_FIRST, "first"))
	{
		fetch->direction = FETCH_ABSOLUTE;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_LAST, "last"))
	{
		fetch->direction = FETCH_ABSOLUTE;
		fetch->how_many  = -1;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_ABSOLUTE, "absolute"))
	{
		fetch->direction = FETCH_ABSOLUTE;
		fetch->expr = read_sql_expression2(K_FROM, K_IN,
										   "FROM or IN",
										   NULL);
		check_FROM = false;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_RELATIVE, "relative"))
	{
		fetch->direction = FETCH_RELATIVE;
		fetch->expr = read_sql_expression2(K_FROM, K_IN,
										   "FROM or IN",
										   NULL);
		check_FROM = false;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_ALL, "all"))
	{
		fetch->how_many = FETCH_ALL;
		fetch->returns_multiple_rows = true;
	}
	else if (tok_is_keyword(tok, &yylval,
							K_FORWARD, "forward"))
	{
		complete_direction(fetch, &check_FROM);
	}
	else if (tok_is_keyword(tok, &yylval,
							K_BACKWARD, "backward"))
	{
		fetch->direction = FETCH_BACKWARD;
		complete_direction(fetch, &check_FROM);
	}
	else if (tok == K_FROM || tok == K_IN)
	{
		/* empty direction */
		check_FROM = false;
	}
	else if (tok == T_DATUM)
	{
		/* Assume there's no direction clause and tok is a cursor name */
		plmysql_push_back_token(tok);
		check_FROM = false;
	}
	else
	{
		/*
		 * Assume it's a count expression with no preceding keyword.
		 * Note: we allow this syntax because core SQL does, but it's
		 * ambiguous with the case of an omitted direction clause; for
		 * instance, "MOVE n IN c" will fail if n is a variable, because the
		 * preceding else-arm will trigger.  Perhaps this can be improved
		 * someday, but it hardly seems worth a lot of work.
		 */
		plmysql_push_back_token(tok);
		fetch->expr = read_sql_expression2(K_FROM, K_IN,
										   "FROM or IN",
										   NULL);
		fetch->returns_multiple_rows = true;
		check_FROM = false;
	}

	/* check FROM or IN keyword after direction's specification */
	if (check_FROM)
	{
		tok = yylex();
		if (tok != K_FROM && tok != K_IN)
			yyerror("expected FROM or IN");
	}

	return fetch;
}

/*
 * Process remainder of FETCH/MOVE direction after FORWARD or BACKWARD.
 * Allows these cases:
 *   FORWARD expr,  FORWARD ALL,  FORWARD
 *   BACKWARD expr, BACKWARD ALL, BACKWARD
 */
static void
complete_direction(PLMySQL_stmt_fetch *fetch,  bool *check_FROM)
{
	int			tok;

	tok = yylex();
	if (tok == 0)
		yyerror("unexpected end of function definition");

	if (tok == K_FROM || tok == K_IN)
	{
		*check_FROM = false;
		return;
	}

	if (tok == K_ALL)
	{
		fetch->how_many = FETCH_ALL;
		fetch->returns_multiple_rows = true;
		*check_FROM = true;
		return;
	}

	plmysql_push_back_token(tok);
	fetch->expr = read_sql_expression2(K_FROM, K_IN,
									   "FROM or IN",
									   NULL);
	fetch->returns_multiple_rows = true;
	*check_FROM = false;
}


static PLMySQL_stmt *
make_return_stmt(int location)
{
	PLMySQL_stmt_return *new;

	new = palloc0(sizeof(PLMySQL_stmt_return));
	new->cmd_type = PLMYSQL_STMT_RETURN;
	new->lineno   = plmysql_location_to_lineno(location);
	new->stmtid	  = ++plmysql_curr_compile->nstatements;
	new->expr	  = NULL;
	new->retvarno = -1;

	if (plmysql_curr_compile->fn_retset)
	{
		if (yylex() != ';')
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("RETURN cannot have a parameter in function returning set"),
					 errhint("Use RETURN NEXT or RETURN QUERY."),
					 parser_errposition(yylloc)));
	}
	else if (plmysql_curr_compile->fn_rettype == VOIDOID)
	{
		if (yylex() != ';')
		{
			if (plmysql_curr_compile->fn_prokind == PROKIND_PROCEDURE)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("RETURN cannot have a parameter in a procedure"),
						 parser_errposition(yylloc)));
			else
				ereport(ERROR,
						(errcode(ERRCODE_DATATYPE_MISMATCH),
						 errmsg("RETURN cannot have a parameter in function returning void"),
						 parser_errposition(yylloc)));
		}
	}
	else if (plmysql_curr_compile->out_param_varno >= 0)
	{
		if (yylex() != ';')
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("RETURN cannot have a parameter in function with OUT parameters"),
					 parser_errposition(yylloc)));
		new->retvarno = plmysql_curr_compile->out_param_varno;
	}
	else
	{
		/*
		 * We want to special-case simple variable references for efficiency.
		 * So peek ahead to see if that's what we have.
		 */
		int		tok = yylex();

		if (tok == T_DATUM && plmysql_peek() == ';' &&
			(yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_VAR ||
			 yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_PROMISE ||
			 yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_ROW ||
			 yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_REC))
		{
			new->retvarno = yylval.wdatum.datum->dno;
			/* eat the semicolon token that we only peeked at above */
			tok = yylex();
			Assert(tok == ';');
		}
		else
		{
			/*
			 * Not (just) a variable name, so treat as expression.
			 *
			 * Note that a well-formed expression is _required_ here;
			 * anything else is a compile-time error.
			 */
			plmysql_push_back_token(tok);
			new->expr = read_sql_expression(';', ";");
		}
	}

	return (PLMySQL_stmt *) new;
}


static PLMySQL_stmt *
make_return_next_stmt(int location)
{
	PLMySQL_stmt_return_next *new;

	if (!plmysql_curr_compile->fn_retset)
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("cannot use RETURN NEXT in a non-SETOF function"),
				 parser_errposition(location)));

	new = palloc0(sizeof(PLMySQL_stmt_return_next));
	new->cmd_type	= PLMYSQL_STMT_RETURN_NEXT;
	new->lineno		= plmysql_location_to_lineno(location);
	new->stmtid		= ++plmysql_curr_compile->nstatements;
	new->expr		= NULL;
	new->retvarno	= -1;

	if (plmysql_curr_compile->out_param_varno >= 0)
	{
		if (yylex() != ';')
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("RETURN NEXT cannot have a parameter in function with OUT parameters"),
					 parser_errposition(yylloc)));
		new->retvarno = plmysql_curr_compile->out_param_varno;
	}
	else
	{
		/*
		 * We want to special-case simple variable references for efficiency.
		 * So peek ahead to see if that's what we have.
		 */
		int		tok = yylex();

		if (tok == T_DATUM && plmysql_peek() == ';' &&
			(yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_VAR ||
			 yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_PROMISE ||
			 yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_ROW ||
			 yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_REC))
		{
			new->retvarno = yylval.wdatum.datum->dno;
			/* eat the semicolon token that we only peeked at above */
			tok = yylex();
			Assert(tok == ';');
		}
		else
		{
			/*
			 * Not (just) a variable name, so treat as expression.
			 *
			 * Note that a well-formed expression is _required_ here;
			 * anything else is a compile-time error.
			 */
			plmysql_push_back_token(tok);
			new->expr = read_sql_expression(';', ";");
		}
	}

	return (PLMySQL_stmt *) new;
}


static PLMySQL_stmt *
make_return_query_stmt(int location)
{
	PLMySQL_stmt_return_query *new;
	int			tok;

	if (!plmysql_curr_compile->fn_retset)
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("cannot use RETURN QUERY in a non-SETOF function"),
				 parser_errposition(location)));

	new = palloc0(sizeof(PLMySQL_stmt_return_query));
	new->cmd_type = PLMYSQL_STMT_RETURN_QUERY;
	new->lineno = plmysql_location_to_lineno(location);
	new->stmtid = ++plmysql_curr_compile->nstatements;

	/* check for RETURN QUERY EXECUTE */
	if ((tok = yylex()) != K_EXECUTE)
	{
		/* ordinary static query */
		plmysql_push_back_token(tok);
		new->query = read_sql_stmt();
	}
	else
	{
		/* dynamic SQL */
		int		term;

		new->dynquery = read_sql_expression2(';', K_USING, "; or USING",
											 &term);
		if (term == K_USING)
		{
			do
			{
				PLMySQL_expr *expr;

				expr = read_sql_expression2(',', ';', ", or ;", &term);
				new->params = lappend(new->params, expr);
			} while (term == ',');
		}
	}

	return (PLMySQL_stmt *) new;
}


/* convenience routine to fetch the name of a T_DATUM */
static char *
NameOfDatum(PLwdatum *wdatum)
{
	if (wdatum->ident)
		return wdatum->ident;
	Assert(wdatum->idents != NIL);
	return NameListToString(wdatum->idents);
}

static void
check_assignable(PLMySQL_datum *datum, int location)
{
	switch (datum->dtype)
	{
		case PLMYSQL_DTYPE_VAR:
		case PLMYSQL_DTYPE_PROMISE:
		case PLMYSQL_DTYPE_REC:
			if (((PLMySQL_variable *) datum)->isconst)
				ereport(ERROR,
						(errcode(ERRCODE_ERROR_IN_ASSIGNMENT),
						 errmsg("variable \"%s\" is declared CONSTANT",
								((PLMySQL_variable *) datum)->refname),
						 parser_errposition(location)));
			break;
		case PLMYSQL_DTYPE_ROW:
			/* always assignable; member vars were checked at compile time */
			break;
		case PLMYSQL_DTYPE_RECFIELD:
			/* assignable if parent record is */
			check_assignable(plmysql_Datums[((PLMySQL_recfield *) datum)->recparentno],
							 location);
			break;
		default:
			elog(ERROR, "unrecognized dtype: %d", datum->dtype);
			break;
	}
}

/*
 * Read the argument of an INTO clause.  On entry, we have just read the
 * INTO keyword.
 */
static void
read_into_target(PLMySQL_variable **target, bool *strict)
{
	int			tok;

	/* Set default results */
	*target = NULL;
	if (strict)
		*strict = false;

	tok = yylex();

	/*
	 * Currently, a row or record variable can be the single INTO target,
	 * but not a member of a multi-target list.  So we throw error if there
	 * is a comma after it, because that probably means the user tried to
	 * write a multi-target list.  If this ever gets generalized, we should
	 * probably refactor read_into_scalar_list so it handles all cases.
	 */
	switch (tok)
	{
		case T_DATUM:
			if (yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_ROW ||
				yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_REC)
			{
				check_assignable(yylval.wdatum.datum, yylloc);
				*target = (PLMySQL_variable *) yylval.wdatum.datum;

				if ((tok = yylex()) == ',')
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("record variable cannot be part of multiple-item INTO list"),
							 parser_errposition(yylloc)));
				plmysql_push_back_token(tok);
			}
			else
			{
				*target = (PLMySQL_variable *)
					read_into_scalar_list(NameOfDatum(&(yylval.wdatum)),
										  yylval.wdatum.datum, yylloc);
			}
			break;

		default:
			/* just to give a better message than "syntax error" */
			current_token_is_not_variable(tok);
	}
}

/*
 * Given the first datum and name in the INTO list, continue to read
 * comma-separated scalar variables until we run out. Then construct
 * and return a fake "row" variable that represents the list of
 * scalars.
 */
static PLMySQL_row *
read_into_scalar_list(char *initial_name,
					  PLMySQL_datum *initial_datum,
					  int initial_location)
{
	int				 nfields;
	char			*fieldnames[1024];
	int				 varnos[1024];
	PLMySQL_row		*row;
	int				 tok;

	check_assignable(initial_datum, initial_location);
	fieldnames[0] = initial_name;
	varnos[0]	  = initial_datum->dno;
	nfields		  = 1;

	while ((tok = yylex()) == ',')
	{
		/* Check for array overflow */
		if (nfields >= 1024)
			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("too many INTO variables specified"),
					 parser_errposition(yylloc)));

		tok = yylex();
		switch (tok)
		{
			case T_DATUM:
				check_assignable(yylval.wdatum.datum, yylloc);
				if (yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_ROW ||
					yylval.wdatum.datum->dtype == PLMYSQL_DTYPE_REC)
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("\"%s\" is not a scalar variable",
									NameOfDatum(&(yylval.wdatum))),
							 parser_errposition(yylloc)));
				fieldnames[nfields] = NameOfDatum(&(yylval.wdatum));
				varnos[nfields++]	= yylval.wdatum.datum->dno;
				break;

			default:
				/* just to give a better message than "syntax error" */
				current_token_is_not_variable(tok);
		}
	}

	/*
	 * We read an extra, non-comma token from yylex(), so push it
	 * back onto the input stream
	 */
	plmysql_push_back_token(tok);

	row = palloc0(sizeof(PLMySQL_row));
	row->dtype = PLMYSQL_DTYPE_ROW;
	row->refname = "(unnamed row)";
	row->lineno = plmysql_location_to_lineno(initial_location);
	row->rowtupdesc = NULL;
	row->nfields = nfields;
	row->fieldnames = palloc(sizeof(char *) * nfields);
	row->varnos = palloc(sizeof(int) * nfields);
	while (--nfields >= 0)
	{
		row->fieldnames[nfields] = fieldnames[nfields];
		row->varnos[nfields] = varnos[nfields];
	}

	plmysql_adddatum((PLMySQL_datum *)row);

	return row;
}

/*
 * Convert a single scalar into a "row" list.  This is exactly
 * like read_into_scalar_list except we never consume any input.
 *
 * Note: lineno could be computed from location, but since callers
 * have it at hand already, we may as well pass it in.
 */
static PLMySQL_row *
make_scalar_list1(char *initial_name,
				  PLMySQL_datum *initial_datum,
				  int lineno, int location)
{
	PLMySQL_row		*row;

	check_assignable(initial_datum, location);

	row = palloc0(sizeof(PLMySQL_row));
	row->dtype = PLMYSQL_DTYPE_ROW;
	row->refname = "(unnamed row)";
	row->lineno = lineno;
	row->rowtupdesc = NULL;
	row->nfields = 1;
	row->fieldnames = palloc(sizeof(char *));
	row->varnos = palloc(sizeof(int));
	row->fieldnames[0] = initial_name;
	row->varnos[0] = initial_datum->dno;

	plmysql_adddatum((PLMySQL_datum *)row);

	return row;
}

/*
 * When the PL/MySQL parser expects to see a SQL statement, it is very
 * liberal in what it accepts; for example, we often assume an
 * unrecognized keyword is the beginning of a SQL statement. This
 * avoids the need to duplicate parts of the SQL grammar in the
 * PL/MySQL grammar, but it means we can accept wildly malformed
 * input. To try and catch some of the more obviously invalid input,
 * we run the strings we expect to be SQL statements through the main
 * SQL parser.
 *
 * We only invoke the raw parser (not the analyzer); this doesn't do
 * any database access and does not check any semantic rules, it just
 * checks for basic syntactic correctness. We do this here, rather
 * than after parsing has finished, because a malformed SQL statement
 * may cause the PL/MySQL parser to become confused about statement
 * borders. So it is best to bail out as early as we can.
 *
 * It is assumed that "stmt" represents a copy of the function source text
 * beginning at offset "location".  We use this assumption to transpose
 * any error cursor position back to the function source text.
 * If no error cursor is provided, we'll just point at "location".
 */
static void
check_sql_expr(const char *stmt, RawParseMode parseMode, int location)
{
	sql_error_callback_arg cbarg;
	ErrorContextCallback  syntax_errcontext;
	MemoryContext oldCxt;

	if (!plmysql_check_syntax)
		return;

	cbarg.location = location;

	syntax_errcontext.callback = plmysql_sql_error_callback;
	syntax_errcontext.arg = &cbarg;
	syntax_errcontext.previous = error_context_stack;
	error_context_stack = &syntax_errcontext;

	oldCxt = MemoryContextSwitchTo(plmysql_compile_tmp_cxt);
	(void) raw_parser(stmt, parseMode);
	MemoryContextSwitchTo(oldCxt);

	/* Restore former ereport callback */
	error_context_stack = syntax_errcontext.previous;
}

static void
plmysql_sql_error_callback(void *arg)
{
	sql_error_callback_arg *cbarg = (sql_error_callback_arg *) arg;
	int			errpos;

	/*
	 * First, set up internalerrposition to point to the start of the
	 * statement text within the function text.  Note this converts
	 * location (a byte offset) to a character number.
	 */
	parser_errposition(cbarg->location);

	/*
	 * If the core parser provided an error position, transpose it.
	 * Note we are dealing with 1-based character numbers at this point.
	 */
	errpos = geterrposition();
	if (errpos > 0)
	{
		int		myerrpos = getinternalerrposition();

		if (myerrpos > 0)		/* safety check */
			internalerrposition(myerrpos + errpos - 1);
	}

	/* In any case, flush errposition --- we want internalerrposition only */
	errposition(0);
}

/*
 * Parse a SQL datatype name and produce a PLMySQL_type structure.
 *
 * The heavy lifting is done elsewhere.  Here we are only concerned
 * with setting up an errcontext link that will let us give an error
 * cursor pointing into the plmysql function source, if necessary.
 * This is handled the same as in check_sql_expr(), and we likewise
 * expect that the given string is a copy from the source text.
 */
static PLMySQL_type *
parse_datatype(const char *string, int location)
{
	TypeName   *typeName;
	Oid			type_id;
	int32		typmod;
	sql_error_callback_arg cbarg;
	ErrorContextCallback  syntax_errcontext;

	cbarg.location = location;

	syntax_errcontext.callback = plmysql_sql_error_callback;
	syntax_errcontext.arg = &cbarg;
	syntax_errcontext.previous = error_context_stack;
	error_context_stack = &syntax_errcontext;

	/* Let the main parser try to parse it under standard SQL rules */
	typeName = typeStringToTypeName(string);
	typenameTypeIdAndMod(NULL, typeName, &type_id, &typmod);

	/* Restore former ereport callback */
	error_context_stack = syntax_errcontext.previous;

	/* Okay, build a PLMySQL_type data structure for it */
	return plmysql_build_datatype(type_id, typmod,
								  plmysql_curr_compile->fn_input_collation,
								  typeName);
}

/*
 * Check block starting and ending labels match.
 */
static void
check_labels(const char *start_label, const char *end_label, int end_location)
{
	if (end_label)
	{
		if (!start_label)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("end label \"%s\" specified for unlabeled block",
							end_label),
					 parser_errposition(end_location)));

		if (strcmp(start_label, end_label) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("end label \"%s\" differs from block's label \"%s\"",
							end_label, start_label),
					 parser_errposition(end_location)));
	}
}

/*
 * Read the arguments (if any) for a cursor, followed by the until token
 *
 * If cursor has no args, just swallow the until token and return NULL.
 * If it does have args, we expect to see "( arg [, arg ...] )" followed
 * by the until token, where arg may be a plain expression, or a named
 * parameter assignment of the form argname := expr. Consume all that and
 * return a SELECT query that evaluates the expression(s) (without the outer
 * parens).
 */
static PLMySQL_expr *
read_cursor_args(PLMySQL_var *cursor, int until)
{
	PLMySQL_expr *expr;
	PLMySQL_row *row;
	int			tok;
	int			argc;
	char	  **argv;
	StringInfoData ds;
	bool		any_named = false;

	tok = yylex();
	if (cursor->cursor_explicit_argrow < 0)
	{
		/* No arguments expected */
		if (tok == '(')
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("cursor \"%s\" has no arguments",
							cursor->refname),
					 parser_errposition(yylloc)));

		if (tok != until)
			yyerror("syntax error");

		return NULL;
	}

	/* Else better provide arguments */
	if (tok != '(')
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("cursor \"%s\" has arguments",
						cursor->refname),
				 parser_errposition(yylloc)));

	/*
	 * Read the arguments, one by one.
	 */
	row = (PLMySQL_row *) plmysql_Datums[cursor->cursor_explicit_argrow];
	argv = (char **) palloc0(row->nfields * sizeof(char *));

	for (argc = 0; argc < row->nfields; argc++)
	{
		PLMySQL_expr *item;
		int		endtoken;
		int		argpos;
		int		tok1,
				tok2;
		int		arglocation;

		/* Check if it's a named parameter: "param := value" */
		plmysql_peek2(&tok1, &tok2, &arglocation, NULL);
		if (tok1 == IDENT && tok2 == COLON_EQUALS)
		{
			char   *argname;
			IdentifierLookup save_IdentifierLookup;

			/* Read the argument name, ignoring any matching variable */
			save_IdentifierLookup = plmysql_IdentifierLookup;
			plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
			yylex();
			argname = yylval.str;
			plmysql_IdentifierLookup = save_IdentifierLookup;

			/* Match argument name to cursor arguments */
			for (argpos = 0; argpos < row->nfields; argpos++)
			{
				if (strcmp(row->fieldnames[argpos], argname) == 0)
					break;
			}
			if (argpos == row->nfields)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("cursor \"%s\" has no argument named \"%s\"",
								cursor->refname, argname),
						 parser_errposition(yylloc)));

			/*
			 * Eat the ":=". We already peeked, so the error should never
			 * happen.
			 */
			tok2 = yylex();
			if (tok2 != COLON_EQUALS)
				yyerror("syntax error");

			any_named = true;
		}
		else
			argpos = argc;

		if (argv[argpos] != NULL)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("value for parameter \"%s\" of cursor \"%s\" specified more than once",
							row->fieldnames[argpos], cursor->refname),
					 parser_errposition(arglocation)));

		/*
		 * Read the value expression. To provide the user with meaningful
		 * parse error positions, we check the syntax immediately, instead of
		 * checking the final expression that may have the arguments
		 * reordered.
		 */
		item = read_sql_construct(',', ')', 0,
								  ",\" or \")",
								  RAW_PARSE_PLPGSQL_EXPR,
								  true, true,
								  NULL, &endtoken);

		argv[argpos] = item->query;

		if (endtoken == ')' && !(argc == row->nfields - 1))
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("not enough arguments for cursor \"%s\"",
							cursor->refname),
					 parser_errposition(yylloc)));

		if (endtoken == ',' && (argc == row->nfields - 1))
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("too many arguments for cursor \"%s\"",
							cursor->refname),
					 parser_errposition(yylloc)));
	}

	/* Make positional argument list */
	initStringInfo(&ds);
	for (argc = 0; argc < row->nfields; argc++)
	{
		Assert(argv[argc] != NULL);

		/*
		 * Because named notation allows permutated argument lists, include
		 * the parameter name for meaningful runtime errors.
		 */
		appendStringInfoString(&ds, argv[argc]);
		if (any_named)
			appendStringInfo(&ds, " AS %s",
							 quote_identifier(row->fieldnames[argc]));
		if (argc < row->nfields - 1)
			appendStringInfoString(&ds, ", ");
	}

	expr = palloc0(sizeof(PLMySQL_expr));
	expr->query			= pstrdup(ds.data);
	expr->parseMode		= RAW_PARSE_PLPGSQL_EXPR;
	expr->plan			= NULL;
	expr->paramnos		= NULL;
	expr->target_param	= -1;
	expr->ns            = plmysql_ns_top();
	pfree(ds.data);

	/* Next we'd better find the until token */
	tok = yylex();
	if (tok != until)
		yyerror("syntax error");

	return expr;
}

/*
 * Fix up CASE statement
 */
static PLMySQL_stmt *
make_case(int location, PLMySQL_expr *t_expr,
		  List *case_when_list, List *else_stmts)
{
	PLMySQL_stmt_case	*new;

	new = palloc(sizeof(PLMySQL_stmt_case));
	new->cmd_type = PLMYSQL_STMT_CASE;
	new->lineno = plmysql_location_to_lineno(location);
	new->stmtid = ++plmysql_curr_compile->nstatements;
	new->t_expr = t_expr;
	new->t_varno = 0;
	new->case_when_list = case_when_list;
	new->have_else = (else_stmts != NIL);
	/* Get rid of list-with-NULL hack */
	if (list_length(else_stmts) == 1 && linitial(else_stmts) == NULL)
		new->else_stmts = NIL;
	else
		new->else_stmts = else_stmts;

	/*
	 * When test expression is present, we create a var for it and then
	 * convert all the WHEN expressions to "VAR IN (original_expression)".
	 * This is a bit klugy, but okay since we haven't yet done more than
	 * read the expressions as text.  (Note that previous parsing won't
	 * have complained if the WHEN ... THEN expression contained multiple
	 * comma-separated values.)
	 */
	if (t_expr)
	{
		char	varname[32];
		PLMySQL_var *t_var;
		ListCell *l;

		/* use a name unlikely to collide with any user names */
		snprintf(varname, sizeof(varname), "__case__variable_%d__",
				 plmysql_nDatums);

		/*
		 * We don't yet know the result datatype of t_expr.  Build the
		 * variable as if it were INT4; we'll fix this at runtime if needed.
		 *
		 * The name is all-lowercase on purpose: it is spliced into the WHEN
		 * expressions as a bare identifier, and both the standard and MySQL
		 * dialect parsers fold bare identifiers to lowercase, while the
		 * namespace lookup at plan time is case-sensitive.
		 */
		t_var = (PLMySQL_var *)
			plmysql_build_variable(varname, new->lineno,
								   plmysql_build_datatype(INT4OID,
														  -1,
														  InvalidOid,
														  NULL),
								   true);
		new->t_varno = t_var->dno;

		foreach(l, case_when_list)
		{
			PLMySQL_case_when *cwt = (PLMySQL_case_when *) lfirst(l);
			PLMySQL_expr *expr = cwt->expr;
			StringInfoData	ds;

			/* We expect to have expressions not statements */
			Assert(expr->parseMode == RAW_PARSE_PLPGSQL_EXPR);

			/* Do the string hacking */
			initStringInfo(&ds);

			/*
			 * The case variable's name is left UNQUOTED on purpose: plpgsql
			 * spells it as a double-quoted identifier, but the MySQL dialect
			 * treats double quotes as string literals, which would turn the
			 * comparison into "string IN (expr)" and fail at run time.  The
			 * bare name is a plain identifier in both dialects, so the parser
			 * hook (mys_parse_expr.c honors pre_columnref_hook just like the
			 * stock analyzer) resolves it to the case variable's parameter.
			 */
			appendStringInfo(&ds, "%s IN (%s)",
							 varname, expr->query);

			pfree(expr->query);
			expr->query = pstrdup(ds.data);
			/* Adjust expr's namespace to include the case variable */
			expr->ns = plmysql_ns_top();

			pfree(ds.data);
		}
	}

	return (PLMySQL_stmt *) new;
}

/*
 * ---------------------------------------------------------------------
 * MySQL DECLARE HANDLER / SIGNAL compile-time support
 * ---------------------------------------------------------------------
 *
 * MySQL declares condition handlers inside the DECLARE section of a block;
 * the handlers attach to that block and (with lower precedence) to enclosing
 * blocks.  The grammar builds the block node only after the whole declare
 * section and body have been parsed, so handlers are collected in
 * mysql_current_handlers while a block is being parsed; pl_block's opening
 * mid-rule saves and clears the list, and the block's closing action picks
 * it up.
 */

static List *mysql_current_handlers = NIL;
/*
 * (mysql_current_handlers / mysql_decl_phase are declared in the prologue so
 * grammar actions can reach them; the initializers live here.)
 */

/*
 * DECLARE ordering: MySQL requires variables and conditions to be declared
 * first, then cursors, then handlers.  Phases: 0 = variables/conditions,
 * 1 = cursors, 2 = handlers.  A declaration of kind k is only legal while
 * the phase is <= k; declaring it moves the phase to k.
 */
static int	mysql_decl_phase = 0;

/*
 * mysql_current_handlers/mysql_decl_phase are per-block, but a HANDLER's own
 * action can itself be a "BEGIN ... END" block (e.g. "DECLARE EXIT HANDLER
 * FOR ... BEGIN ... END;") -- pl_block's opening mid-rule action runs
 * mysql_decl_begin_block() for that nested block too, before the outer
 * HANDLER declaration that triggered it has been fully reduced.  Without
 * saving and restoring the outer block's state around that nested reset,
 * entering the nested block silently discards any handlers already
 * collected for the outer block and resets its phase to 0, so a variable
 * DECLARE the outer block should reject as coming after a HANDLER (which
 * moved its phase to 2) is instead let through once the nested block exits.
 * This stack is what makes mysql_decl_begin_block()/_end_block() a true
 * push/pop pair instead of a bare reset.
 */
typedef struct MysqlDeclBlockState
{
	int			phase;
	List	   *handlers;
} MysqlDeclBlockState;

static List *mysql_decl_block_stack = NIL; /* of MysqlDeclBlockState *,
											 * innermost block first */

static void
mysql_decl_begin_block(void)
{
	MysqlDeclBlockState *saved = palloc(sizeof(MysqlDeclBlockState));

	saved->phase = mysql_decl_phase;
	saved->handlers = mysql_current_handlers;
	mysql_decl_block_stack = lcons(saved, mysql_decl_block_stack);

	mysql_current_handlers = NIL;
	mysql_decl_phase = 0;
}

static List *
mysql_decl_end_block(void)
{
	List	   *handlers = mysql_current_handlers;
	MysqlDeclBlockState *saved = (MysqlDeclBlockState *) linitial(mysql_decl_block_stack);

	mysql_decl_block_stack = list_delete_first(mysql_decl_block_stack);

	mysql_current_handlers = saved->handlers;
	mysql_decl_phase = saved->phase;
	pfree(saved);

	return handlers;
}

/*
 * Reset all DECLARE-ordering/handler-collection state before compiling a
 * routine from scratch.  Needed because an error raised while compiling one
 * routine longjmps out of the parser without running mysql_decl_end_block(),
 * which would otherwise leave a previous compile's nested-block entries on
 * mysql_decl_block_stack for the next compile's pops to wrongly consume.
 */
void
plmysql_decl_reset_for_compile(void)
{
	mysql_current_handlers = NIL;
	mysql_decl_phase = 0;
	mysql_decl_block_stack = NIL;
}

/*
 * max_allowed: the latest phase in which this declaration kind is legal.
 * (0 = variables/conditions, 1 = cursors, 2 = handlers.)
 */
static void
mysql_decl_check_phase(int max_allowed, int location)
{
	static const char *const kinds[3] = {
		"variables and conditions",
		"cursors",
		"handlers"
	};

	if (mysql_decl_phase > max_allowed)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("%s must be declared before %s",
						kinds[max_allowed], kinds[mysql_decl_phase]),
				 parser_errposition(location)));

	mysql_decl_phase = max_allowed;
}

static int
mysql_make_sqlstate(const char *s)
{
	return MAKE_SQLSTATE(s[0], s[1], s[2], s[3], s[4]);
}

static void
mysql_check_sqlstate_literal(const char *s, int location)
{
	if (strlen(s) != 5 ||
		strspn(s, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") != 5)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("invalid SQLSTATE code \"%s\"", s),
				 parser_errposition(location)));
}

/*
 * Resolve a HANDLER/SIGNAL condition that is spelled as an identifier: a
 * declared CONDITION datum (from DECLARE cond CONDITION FOR ...), the
 * SQLEXCEPTION / SQLWARNING classes, or one of the standard condition names
 * recognized by plmysql_recognize_err_condition().
 */
static PLMySQL_condition *
mysql_resolve_condition_value(const char *name, int location)
{
	PLMySQL_condition *cond = palloc0(sizeof(PLMySQL_condition));
	PLMySQL_nsitem *ns;

	if (pg_strcasecmp(name, "sqlexception") == 0)
	{
		cond->sqlerrstate = PLMYSQL_COND_SQLEXCEPTION;
		cond->condname = pstrdup("SQLEXCEPTION");
		return cond;
	}

	/*
	 * A named condition declared in this or an enclosing block.  The scanner
	 * is in DECLARE lookup mode while parsing the declare section, so the
	 * name arrives as a plain word; look it up manually.
	 */
	ns = plmysql_ns_lookup(plmysql_ns_top(), false, name, NULL, NULL, NULL);
	if (ns != NULL && ns->itemtype == PLMYSQL_NSTYPE_VAR &&
		plmysql_Datums[ns->itemno]->dtype == PLMYSQL_DTYPE_COND)
	{
		PLMySQL_cond *c = (PLMySQL_cond *) plmysql_Datums[ns->itemno];

		cond->sqlerrstate = c->sqlstate[0]
			? mysql_make_sqlstate(c->sqlstate)
			: 0;
		cond->mysql_errno = c->mysql_errno;
		cond->condname = pstrdup(name);
		return cond;
	}

	/*
	 * SQLWARNING is MySQL's warning class (SQLSTATE class '01'); everything
	 * else goes through the standard condition-name table (which also
	 * accepts 5-character SQLSTATE codes and names like NO_DATA_FOUND).
	 */
	if (pg_strcasecmp(name, "sqlwarning") == 0)
		cond->sqlerrstate = ERRCODE_WARNING;
	else
		cond->sqlerrstate = plmysql_recognize_err_condition(name, true);
	cond->condname = pstrdup(name);

	return cond;
}

/*
 * SIGNAL's condition must resolve to a concrete SQLSTATE (classes and raw
 * errnos are not signalable).  Named conditions declared by errno get their
 * SQLSTATE from the reverse error-code map, defaulting to 45000
 * (unhandled user-defined exception), which is what MySQL effectively
 * reports for user-signalled errors without a specific code.
 */
static char *
mysql_signal_condition_sqlstate(const char *name, int location)
{
	PLMySQL_condition *cond;
	static char sqlstate[6];

	cond = mysql_resolve_condition_value(name, location);

	if (cond->sqlerrstate == PLMYSQL_COND_SQLEXCEPTION ||
		ERRCODE_IS_CATEGORY(cond->sqlerrstate))
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("SIGNAL cannot use a condition class"),
				 parser_errposition(location)));

	if (cond->sqlerrstate != 0)
		return pstrdup(unpack_sql_state(cond->sqlerrstate));

	if (cond->mysql_errno > 0)
	{
		plmysql_errno_to_sqlstate(cond->mysql_errno, sqlstate);
		return pstrdup(sqlstate);
	}

	return pstrdup("45000");
}

/*
 * Read the "SET MESSAGE_TEXT = ..., MYSQL_ERRNO = ..." clause of a SIGNAL
 * statement.  Returns NIL when the clause is absent.  The terminating ';'
 * is left for the grammar (pushed back) when the clause is present.
 */
static List *
mysql_read_signal_items(void)
{
	List	   *items = NIL;
	int			tok;

	tok = yylex();
	if (tok != K_SET)
	{
		plmysql_push_back_token(tok);
		return NIL;
	}

	for (;;)
	{
		PLMySQL_signal_item_type kind;
		PLMySQL_signal_item *item;
		PLMySQL_expr *expr;
		int			endtok;

		tok = yylex();
		if (tok_is_keyword(tok, &yylval, K_MESSAGE_TEXT, "message_text"))
			kind = PLMYSQL_SIGNAL_MESSAGE_TEXT;
		else if (tok_is_keyword(tok, &yylval, K_MYSQL_ERRNO, "mysql_errno"))
			kind = PLMYSQL_SIGNAL_MYSQL_ERRNO;
		else
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("unsupported SIGNAL information item"),
					 parser_errposition(plmysql_yylloc)));

		tok = yylex();
		if (tok != '=' && tok != COLON_EQUALS)
			yyerror("syntax error");

		expr = read_sql_construct(0, ',', ';', "\",\" or \";\"",
								  RAW_PARSE_PLPGSQL_EXPR,
								  true, true, NULL, &endtok);

		item = palloc0(sizeof(PLMySQL_signal_item));
		item->opt_type = kind;
		item->expr = expr;
		items = lappend(items, item);

		if (endtok == ';')
		{
			plmysql_push_back_token(';');
			break;
		}
	}

	return items;
}

static PLMySQL_stmt *
mysql_build_signal_node(int location, bool is_resignal,
						const char *sqlstate, List *items)
{
	PLMySQL_stmt_signal *new = palloc0(sizeof(PLMySQL_stmt_signal));

	new->cmd_type = PLMYSQL_STMT_SIGNAL;
	new->lineno = plmysql_location_to_lineno(location);
	new->stmtid = ++plmysql_curr_compile->nstatements;
	new->is_resignal = is_resignal;
	new->sqlstate = sqlstate ? pstrdup(sqlstate) : NULL;
	new->cond_datano = -1;
	new->items = items;

	return (PLMySQL_stmt *) new;
}

/*
 * Shared validity checks for GET DIAGNOSTICS items.
 */
static void
mysql_check_getdiag_items(PLMySQL_stmt_getdiag *stmt, int location)
{
	ListCell   *lc;

	foreach(lc, stmt->diag_items)
	{
		PLMySQL_diag_item *ditem = (PLMySQL_diag_item *) lfirst(lc);

		switch (ditem->kind)
		{
			/* these fields are disallowed in stacked case */
			case PLMYSQL_GETDIAG_ROW_COUNT:
				if (stmt->is_stacked && !stmt->is_condition)
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("diagnostics item %s is not allowed in GET STACKED DIAGNOSTICS",
									plmysql_getdiag_kindname(ditem->kind)),
							 parser_errposition(location)));
				break;
			/* these fields are disallowed in current case */
			case PLMYSQL_GETDIAG_ERROR_CONTEXT:
			case PLMYSQL_GETDIAG_ERROR_DETAIL:
			case PLMYSQL_GETDIAG_ERROR_HINT:
			case PLMYSQL_GETDIAG_RETURNED_SQLSTATE:
			case PLMYSQL_GETDIAG_COLUMN_NAME:
			case PLMYSQL_GETDIAG_CONSTRAINT_NAME:
			case PLMYSQL_GETDIAG_DATATYPE_NAME:
			case PLMYSQL_GETDIAG_MESSAGE_TEXT:
			case PLMYSQL_GETDIAG_TABLE_NAME:
			case PLMYSQL_GETDIAG_SCHEMA_NAME:
			case PLMYSQL_GETDIAG_MYSQL_ERRNO:
				if (!stmt->is_stacked && !stmt->is_condition)
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("diagnostics item %s is not allowed in GET CURRENT DIAGNOSTICS",
									plmysql_getdiag_kindname(ditem->kind)),
							 parser_errposition(location)));
				break;
			/* these fields are allowed in either case */
			case PLMYSQL_GETDIAG_CONTEXT:
				break;
		}
	}
}

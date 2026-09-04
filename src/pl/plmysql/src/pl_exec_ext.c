/*-------------------------------------------------------------------------
 *
 * pl_exec_ext.c
 *		MySQL-specific runtime support for the PL/MySQL procedural language.
 *
 * This file holds pieces of the MySQL stored-routine semantics that have no
 * plpgsql counterpart and do not need the executor's internals:
 *
 *   - the hand-maintained MySQL errno <-> SQLSTATE map used by condition
 *     handlers ("DECLARE HANDLER FOR 1062") and by SIGNAL of a condition
 *     declared by errno.  The reverse direction is deliberately a separate,
 *     hand-picked table (not an inversion of the adapter's forward map),
 *     because several MySQL errnos share one SQLSTATE; per the design spec
 *     each entry fixes one canonical SQLSTATE.
 *
 * 版权所有 (c) 2019-2026, 易景科技保留所有权利。
 * Copyright (c) 2019-2026, Halo Tech Co.,Ltd. All rights reserved.
 *
 * IDENTIFICATION
 *	  src/pl/plmysql/src/pl_exec_ext.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "adapter/mysql/adapter.h"
#include "adapter/mysql/common.h"
#include "adapter/mysql/errorConvertor.h"
#include "executor/executor.h"
#include "executor/spi.h"
#include "libpq/libpq-be.h"
#include "miscadmin.h"
#include "plmysql.h"
#include "postmaster/protocol_interface.h"
#include "tcop/cmdtag.h"
#include "tcop/dest.h"

/*
 * Canonical (errno, SQLSTATE) pairs, sorted by errno.  SQLSTATEs follow the
 * MySQL 5.7 manual's appendix of server errors with specific SQLSTATEs;
 * errnos that MySQL reports with the generic HY000 are omitted, since a
 * handler keyed on such an errno can only be raised by SIGNAL anyway (which
 * carries the errno explicitly).
 */
static const struct
{
	int			err;			/* MySQL errno */
	const char	pgstate[6];		/* SQLSTATE PostgreSQL uses for it */
	const char	mystate[6];		/* MySQL's canonical SQLSTATE for it */
} mysql_errno_sqlstate_map[] =
{
	{1022, "23505", "23000"},	/* ER_DUP_KEY */
	{1044, "42501", "42000"},	/* ER_DBACCESS_DENIED_ERROR */
	{1045, "28000", "28000"},	/* ER_ACCESS_DENIED_ERROR */
	{1046, "3D000", "3D000"},	/* ER_NO_DB_ERROR */
	{1048, "23502", "23000"},	/* ER_BAD_NULL_ERROR */
	{1049, "42000", "42000"},	/* ER_BAD_DB_ERROR */
	{1050, "42P07", "42S01"},	/* ER_TABLE_EXISTS_ERROR */
	{1052, "42702", "23000"},	/* ER_FIELD_SPECIFIED_TWICE */
	/* 1146 precedes 1051 on purpose: both map PG's 42P01, and the reverse
	 * lookup takes the first match -- ER_NO_SUCH_TABLE is what MySQL
	 * reports for a missing table. */
	{1146, "42P01", "42S02"},	/* ER_NO_SUCH_TABLE */
	{1054, "42703", "42S22"},	/* ER_BAD_FIELD_ERROR */
	{1059, "42622", "42000"},	/* ER_TOO_LONG_IDENT */
	{1062, "23505", "23000"},	/* ER_DUP_ENTRY */
	{1064, "42601", "42000"},	/* ER_PARSE_ERROR */
	{1149, "42601", "42000"},	/* ER_SYNTAX_ERROR */
	{1169, "23505", "23000"},	/* ER_DUP_UNIQUE */
	{1205, "55P03", "HY000"},	/* ER_LOCK_WAIT_TIMEOUT (generic) */
	{1213, "40P01", "40001"},	/* ER_LOCK_DEADLOCK */
	{1242, "21000", "21000"},	/* ER_SUBQUERY_NO_1_ROW */
	{1264, "22003", "22003"},	/* ER_WARN_DATA_OUT_OF_RANGE */
	{1305, "42883", "42000"},	/* ER_SP_DOES_NOT_EXIST */
	{1317, "57014", "70100"},	/* ER_QUERY_INTERRUPTED */
	{1329, "02000", "02000"},	/* ER_SELECT_REDUCED (no data) */
	{1365, "22012", "22012"},	/* ER_DIVISION_BY_ZERO */
	{1406, "22001", "22001"},	/* ER_DATA_TOO_LONG */
	{1451, "23503", "23000"},	/* ER_ROW_IS_REFERENCED_2 */
	{1452, "23503", "23000"},	/* ER_NO_REFERENCED_ROW_2 */
	{1644, "P0001", "45000"},	/* ER_SIGNAL_EXCEPTION */
};

/*
 * plmysql_errno_to_pgsqlstate
 *		Map a MySQL errno to the SQLSTATE that the *server* raises for the
 *		same condition; used to match "FOR errno" handlers against
 *		server-raised errors.  Returns false when unmapped.
 */
bool
plmysql_errno_to_pgsqlstate(int err, char sqlstate[6])
{
	int			i;

	for (i = 0; i < lengthof(mysql_errno_sqlstate_map); i++)
	{
		if (mysql_errno_sqlstate_map[i].err == err)
		{
			strcpy(sqlstate, mysql_errno_sqlstate_map[i].pgstate);
			return true;
		}
	}
	return false;
}

/*
 * plmysql_errno_to_sqlstate
 *		Map a MySQL errno to MySQL's canonical SQLSTATE; used when a
 *		condition declared by errno is signalled.  Returns false when
 *		unmapped (the caller decides the fallback, e.g. 45000).
 */
bool
plmysql_errno_to_sqlstate(int err, char sqlstate[6])
{
	int			i;

	for (i = 0; i < lengthof(mysql_errno_sqlstate_map); i++)
	{
		if (mysql_errno_sqlstate_map[i].err == err)
		{
			strcpy(sqlstate, mysql_errno_sqlstate_map[i].mystate);
			return true;
		}
	}
	return false;
}

/*
 * plmysql_sqlstate_to_errno
 *		Inverse lookup used when matching "FOR errno" handlers against
 *		server-raised errors.  Returns 0 when there is no mapping.
 */
int
plmysql_sqlstate_to_errno(const char *sqlstate)
{
	int			i;

	for (i = 0; i < lengthof(mysql_errno_sqlstate_map); i++)
	{
		if (strcmp(mysql_errno_sqlstate_map[i].pgstate, sqlstate) == 0)
			return mysql_errno_sqlstate_map[i].err;
	}
	return 0;
}

/*
 * plmysql_clear_signal_errno
 *		Discard any MySQL errno attached to an in-flight error.  Used by
 *		catch paths (and available to plugins) so a handled SIGNAL cannot
 *		taint a later, unrelated error packet.
 */
void
plmysql_clear_signal_errno(void)
{
	plmysql_last_signal_errno = 0;
	mysSetPendingMySQLErrno(0);
}

/*
 * plmysql_push_execsql_resultset
 *		Stream an already-materialized SPI result set to the MySQL client,
 *		the way MySQL 5.7 lets a PROCEDURE body return an ad-hoc result set
 *		via a bare SELECT with no INTO clause (design spec section 4.7).
 *
 * The caller (exec_stmt_execsql(), pl_exec.c) has already run the SELECT
 * through SPI and is holding its result in tuptab; there is no live Portal
 * for it (SPI never opens one), so this sends the rows directly through a
 * fresh DestReceiver the way commands/functioncmds.c's ExecuteCallStmt()
 * sends a CALL's OUT-param row -- CreateDestReceiver(DestRemote) resolves to
 * the MySQL wire-protocol printTup family whenever the session is on the
 * MySQL protocol (access/common/printtup.c's printtup_create_DR()), which is
 * guaranteed here: plmysql routines can only run in such sessions
 * (pl_handler.c's plmysql_require_mysql_protocol()).
 *
 * "More results" bookkeeping is the moreResultsFlag global that the
 * top-level MySQL multi-statement loop (tcop/postgres.c) also uses, compared
 * here against PLMySQL_function.n_resultsets -- the number of such
 * result-set-producing statements the compiler counted in this routine's
 * body.  This is a static, straight-line count: a bare SELECT that runs
 * repeatedly inside a loop is only counted once, so a loop emitting more
 * than one result set can undercount "how many are left" on later
 * iterations.  That's an accepted limitation (matches the design spec's own
 * framing of this bookkeeping), not a case in scope today.
 *
 * Once this invocation's own result sets are exhausted, moreResultsFlag
 * must fall back to estate->outer_more_results_flag (the flag's value as
 * the top-level multi-statement loop had already set it before this CALL
 * started running), not unconditionally to 0: a CALL is very often not the
 * last statement in its client's multi-statement batch, and stomping that
 * outer signal here made the client believe the whole batch was done as
 * soon as this CALL's own last result set was sent -- silently dropping
 * every statement queued after it and desyncing the wire protocol for the
 * rest of the connection.
 */
void
plmysql_push_execsql_resultset(PLMySQL_execstate *estate,
							   SPITupleTable *tuptab, uint64 ntuples)
{
	DestReceiver *dest;
	TupOutputState *tstate;
	QueryCompletion qc;
	uint64		i;

	estate->resultsets_sent++;

	/*
	 * The packet this call is about to send (via end_command() below) is
	 * never the last packet of the enclosing CALL's own response: a CALL
	 * always has its own trailing completion packet sent afterward (see
	 * CMDTAG_CALL in adapter.c's endCommand(), unconditional sendOKPacket()
	 * for every CALL), whether or not there are more of this routine's own
	 * result sets still to come.  So the flag on *this* packet must always
	 * claim more results exist, regardless of estate->resultsets_sent vs.
	 * estate->func->n_resultsets -- otherwise the client sees this result
	 * set's own "no more results" and considers the whole CALL finished
	 * before that trailing packet (which it doesn't know to expect) has
	 * even been sent, corrupting its read of whatever the connection sends
	 * next.  Only after this packet has been sent do we restore
	 * moreResultsFlag to outer_more_results_flag -- the correct true final
	 * value -- so that trailing CALL completion (sent later, once this
	 * invocation returns) carries it instead.
	 */
	moreResultsFlag = HALO_SVR_MORE_RESULTS_EXISTS;

	dest = CreateDestReceiver(DestRemote);
	tstate = begin_tup_output_tupdesc(dest, tuptab->tupdesc, &TTSOpsHeapTuple);
	for (i = 0; i < ntuples; i++)
	{
		TupleTableSlot *slot = ExecStoreHeapTuple(tuptab->vals[i],
												  tstate->slot, false);

		(void) tstate->dest->receiveSlot(slot, tstate->dest, CMDTAG_SELECT);
	}
	end_tup_output(tstate);

	SetQueryCompletion(&qc, CMDTAG_SELECT, ntuples);
	if (MyProcPort)
		MyProcPort->protocol_handler->end_command(&qc, DestRemote);

	if (estate->resultsets_sent >= estate->func->n_resultsets)
		moreResultsFlag = estate->outer_more_results_flag;

	SPI_freetuptable(tuptab);
}

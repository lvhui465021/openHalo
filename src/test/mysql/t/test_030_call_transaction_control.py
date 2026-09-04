"""C2: COMMIT/ROLLBACK inside a CALLed routine body.

The compat report originally guessed the cause was a missing atomic=false
CallContext on the MySQL-protocol CALL dispatch path.  That dispatch was
already correct (confirmed empirically: mys_utility.c/utility.c's T_CallStmt
branch computes and passes isAtomicContext exactly like standard PostgreSQL's
own CALL path).  The real cause turned out to be PostgreSQL's own
ExecuteCallStmt() (functioncmds.c) applying TWO separate, independent rules,
either one enough on its own to force atomic=true:

  1. "If proconfig is set we can't allow transaction commands ... [it] would
     have to pop the proconfig setting off the stack."  plmysql recorded
     every routine's definer, sql_mode snapshot and timestamps in
     pg_proc.proconfig, so *every* plmysql routine hit this -- not just
     SECURITY DEFINER ones.  Fixed: that metadata now lives in a "plmysql"
     security label instead (mys_plmysql_meta_marker() /
     mys_plmysql_set_meta_label(), mys_utility.c), leaving a regular
     (non-trigger) routine's proconfig empty.

  2. "In security definer procedures, we can't allow transaction commands.
     StartTransaction() insists that the security context stack is empty."
     Also fixed now, but NOT by a storage change: a plmysql routine no
     longer carries the MySQL DEFINER default as pg_proc.prosecdef at all.
     mys_plmysql_redirect_sql_security() (mys_utility.c) records the SQL
     SECURITY characteristic in the "plmysql" security label instead
     (leaving prosecdef false, so ExecuteCallStmt() keeps the CALL
     nonatomic), and plmysql_switch_to_routine_definer() (pl_handler.c)
     switches the effective user to the definer for the invocation --
     with zero security-restriction bits, so StartTransaction()'s
     assertion never fires.  See test_037 for the identity semantics.

Net effect verified below: COMMIT/ROLLBACK inside a CALLed routine body
works for BOTH explicit SQL SECURITY INVOKER and MySQL's own default
(no clause -> DEFINER).
"""

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t030_t",
         "CREATE TABLE t030_t (id INT)")

    # SQL SECURITY INVOKER: COMMIT inside a CALLed procedure must work --
    # this was unconditionally broken (proconfig-based) before the fix.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t030_commit_invoker",
         "CREATE PROCEDURE t030_commit_invoker() SQL SECURITY INVOKER "
         "BEGIN INSERT INTO t030_t VALUES (1); COMMIT; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t030_commit_invoker()")
            cur.fetchall()
            cur.execute("SELECT * FROM t030_t WHERE id = 1")
            assert cur.fetchall() == ((1,),)

    # ROLLBACK inside a CALLed SECURITY INVOKER procedure must actually
    # discard the write.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t030_rollback_invoker",
         "CREATE PROCEDURE t030_rollback_invoker() SQL SECURITY INVOKER "
         "BEGIN INSERT INTO t030_t VALUES (2); ROLLBACK; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t030_rollback_invoker()")
            cur.fetchall()
            cur.execute("SELECT * FROM t030_t WHERE id = 2")
            assert cur.fetchall() == tuple(), \
                "ROLLBACK inside CALL did not discard the write"

    # A SECURITY INVOKER routine's own metadata must not be in proconfig any
    # more -- that's the mechanism rule 1's fix relies on.
    out = cluster.psql(
        "SELECT proconfig FROM pg_proc WHERE proname = 't030_commit_invoker';")
    assert out.strip() == "", \
        "t030_commit_invoker must have an empty proconfig, got %r" % out

    # MySQL's own default (no SQL SECURITY clause -> DEFINER): COMMIT must
    # now work here too.  The DEFINER default is carried as a
    # plmysql.sql_security label item and executed via a run-time identity
    # switch rather than pg_proc.prosecdef, so this CALL stays nonatomic.
    # (Before the rule-2 fix this was pinned to fail with 1105.)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t030_commit_definer",
         "CREATE PROCEDURE t030_commit_definer() "
         "BEGIN INSERT INTO t030_t VALUES (3); COMMIT; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t030_commit_definer()")
            cur.fetchall()
            cur.execute("SELECT * FROM t030_t WHERE id = 3")
            assert cur.fetchall() == ((3,),)

    # ROLLBACK in a default-DEFINER routine must also work now.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t030_rollback_definer",
         "CREATE PROCEDURE t030_rollback_definer() "
         "BEGIN INSERT INTO t030_t VALUES (5); ROLLBACK; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t030_rollback_definer()")
            cur.fetchall()
            cur.execute("SELECT * FROM t030_t WHERE id = 5")
            assert cur.fetchall() == tuple(), \
                "ROLLBACK inside default-DEFINER CALL did not discard the write"

    # The mechanism itself: a plmysql routine must NOT carry prosecdef any
    # more (that is what forced the atomic context), and must carry the
    # characteristic in its label instead.
    out = cluster.psql(
        "SELECT prosecdef FROM pg_proc WHERE proname = 't030_commit_definer';")
    assert out.strip() == "f", \
        "t030_commit_definer must have prosecdef=false, got %r" % out
    out = cluster.psql(
        "SELECT label FROM pg_seclabel s JOIN pg_proc p "
        "ON p.oid = s.objoid WHERE p.proname = 't030_commit_definer' "
        "AND s.provider = 'plmysql';")
    assert "plmysql.sql_security=DEFINER" in out, \
        "t030_commit_definer label must record sql_security=DEFINER, got %r" % out

    # Regression: a routine with no transaction-control statements must be
    # unaffected either way.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t030_plain",
         "CREATE PROCEDURE t030_plain() SQL SECURITY INVOKER "
         "INSERT INTO t030_t VALUES (4)")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t030_plain()")
            cur.fetchall()
            cur.execute("SELECT * FROM t030_t WHERE id = 4")
            assert cur.fetchall() == ((4,),)

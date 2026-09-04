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
     This one is NOT fixed, and can't be by a similar storage change: it is
     tied directly to prosecdef itself, which mys_apply_default_sql_security()
     (mys_gram.y) sets to true by default for any routine with no explicit
     SQL SECURITY clause -- matching MySQL's own DEFINER default (13.1.16).
     Since real MySQL has no equivalent restriction (its DEFINER is a
     privilege-check identity, not a PostgreSQL-style security-context-stack
     push/pop), this is a genuine, deeper PostgreSQL-vs-MySQL semantic gap,
     independent of rule 1 -- and still open.

Net effect verified below: an explicit SQL SECURITY INVOKER routine can now
COMMIT/ROLLBACK in its body (this was unconditionally broken before, for
every routine regardless of security mode).  A routine with no SQL SECURITY
clause -- MySQL's own default, which openHalo maps to DEFINER -- still
cannot, and is expected to keep failing with 1105 until that second,
independent restriction is addressed (a separate, larger question: it would
mean either accepting the gap, or reworking DEFINER to not rely on
PostgreSQL's native prosecdef/security-context-stack machinery at all).
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

    # Known, separate, still-open limitation: MySQL's own default (no SQL
    # SECURITY clause -> DEFINER, prosecdef=true) still hits PostgreSQL's
    # unrelated "no transaction commands in a security-definer procedure"
    # rule -- see the module docstring, rule 2.  Pin this as an explicit
    # regression check (not a silent expectation) so a future fix to rule 2
    # is noticed here, rather than this test just going stale.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t030_commit_definer",
         "CREATE PROCEDURE t030_commit_definer() "
         "BEGIN INSERT INTO t030_t VALUES (3); COMMIT; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("CALL t030_commit_definer()")
                cur.fetchall()
                raise AssertionError(
                    "CALL of a default-SQL-SECURITY (DEFINER) routine with "
                    "COMMIT in its body unexpectedly succeeded -- rule 2 "
                    "(prosecdef forces atomic) appears to be fixed; update "
                    "this test's expectations and its module docstring")
            except pymysql.err.OperationalError as e:
                assert e.args[0] == 1105, \
                    "expected 1105 (still-open DEFINER/atomic gap), got %r" % (e.args,)

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

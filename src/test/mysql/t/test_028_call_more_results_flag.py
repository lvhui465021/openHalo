"""A CALL that streams an ad-hoc result set must correctly signal
"more results exist" so the connection stays in sync for whatever runs
after it -- this is the compat report's C1 item (CALL result sets
desyncing the MySQL wire protocol), confirmed as a real server bug via
the official `mysql` CLI (not a pymysql-specific quirk): a CALL streaming
a bare-SELECT result set, followed by any other statement on the same
connection (another CALL or a plain SELECT, whether or not they arrive
as one multi-statement packet or as separate round-trips), used to
silently drop that following statement's response, or break the
connection outright.

Root cause: a CALL statement's wire response is structurally two parts --
its own ad-hoc result set(s), followed unconditionally by a trailing
"procedure call is done" OK packet (adapter.c's endCommand(), CMDTAG_CALL
branch -- every CALL gets this, resultset or not). Both parts share one
flag, the moreResultsFlag global. plmysql_push_execsql_resultset()
(pl_exec_ext.c) used to compute that flag as if the resultset's own
completion packet were the *final* word for the whole CALL, when it
never is: the CMDTAG_CALL completion always follows it. The fix makes
the resultset's own packet always claim more results exist (since the
CALL's trailing OK is always still coming), and only restores the flag
to what should truly be the final value -- outer_more_results_flag,
snapshotting whatever the top-level dispatch loop had determined about
further statements -- once this invocation's own result sets are
exhausted, so that trailing OK packet (sent after this call returns)
carries the correct final signal instead.

One consequence worth pinning explicitly: a resultset-returning CALL now
reports one extra, empty "result set" (the CMDTAG_CALL completion) after
its own data -- this matches genuine MySQL CALL protocol behavior (every
CALL has this trailing status group, resultset or not) and any correct
client driver's next-result loop is written to skip it. The test below
drains explicitly rather than assuming exactly one result set per CALL.
"""

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _drain_all(cur):
    """Collect every non-empty result set, skipping empty status groups."""
    sets = []
    while True:
        rows = cur.fetchall()
        if rows:
            sets.append(rows)
        if not cur.nextset():
            break
    return sets


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t028_t",
         "CREATE TABLE t028_t (id INT)",
         "INSERT INTO t028_t VALUES (1), (2)",
         "DROP PROCEDURE IF EXISTS t028_a",
         "CREATE PROCEDURE t028_a() SELECT 'AAA' AS tag",
         "DROP PROCEDURE IF EXISTS t028_b",
         "CREATE PROCEDURE t028_b() SELECT 'BBB' AS tag",
         "DROP PROCEDURE IF EXISTS t028_multi",
         "CREATE PROCEDURE t028_multi() "
         "BEGIN SELECT 'first' AS r; SELECT 'second' AS r; END")

    # A resultset-returning CALL that is NOT the last statement in a
    # multi-statement batch (CLIENT_MULTI_STATEMENTS, one packet) must
    # still deliver every following statement's data.
    conn = pymysql.connect(host="127.0.0.1", port=cluster.mysql_port,
                            user="halo", database="public",
                            client_flag=pymysql.constants.CLIENT.MULTI_STATEMENTS)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL t028_a(); CALL t028_b();")
            sets = _drain_all(cur)
            assert sets == [(('AAA',),), (('BBB',),)], sets

        # A multi-resultset CALL (more than one bare SELECT in its own
        # body), also not last in the batch, must deliver all of its own
        # result sets plus whatever follows.
        with conn.cursor() as cur:
            cur.execute("CALL t028_multi(); SELECT 'tail' AS z;")
            sets = _drain_all(cur)
            assert sets == [(('first',),), (('second',),), (('tail',),)], sets
    finally:
        conn.close()

    # The same, but as two independent round-trip commands on one
    # connection (no CLIENT_MULTI_STATEMENTS) -- the shape the bug was
    # originally found in via the official mysql CLI.
    with cluster.mysql(dbname="public") as conn2:
        with conn2.cursor() as cur:
            cur.execute("CALL t028_a()")
            assert cur.fetchall() == (('AAA',),)
            cur.execute("CALL t028_b()")
            assert cur.fetchall() == (('BBB',),)
            cur.execute("SELECT 42")
            assert cur.fetchone() == (42,)

    # A resultset-less CALL followed by something else, and a solo
    # resultset-returning CALL as the only statement on its connection,
    # must both keep working exactly as before (regression check).
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t028_noop",
         "CREATE PROCEDURE t028_noop() INSERT INTO t028_t VALUES (9)")
    with cluster.mysql(dbname="public") as conn3:
        with conn3.cursor() as cur:
            cur.execute("CALL t028_noop()")
            cur.fetchall()
            cur.execute("SELECT id FROM t028_t WHERE id = 9")
            assert cur.fetchall() == ((9,),)

    with cluster.mysql(dbname="public") as conn4:
        with conn4.cursor() as cur:
            cur.execute("CALL t028_a()")
            assert cur.fetchall() == (('AAA',),)

    run_conditional_handler(cluster)


def run_conditional_handler(cluster):
    """A CALL whose *handler* streams the result set (nested handlers, only
    the inner one fires) used to hang the client forever: the compiler's
    static n_resultsets tally counted both handler SELECTs, the runtime sent
    only one, so resultsets_sent < n_resultsets left moreResultsFlag set on
    the CALL's trailing OK -- the client then waited for a second result set
    that never arrived (sp.test's h_es/h_ss/h_xs family, and about 19 corpus
    CALLs in total desynced exactly this way).  The trailing completion now
    always carries the outer flag; pin the exact wire behavior: the result
    set's own EOF claims "more" (the trailing OK is still coming), and the
    trailing OK terminates the response cleanly.
    """
    _ddl(cluster,
         "DROP TABLE IF EXISTS t028_dup",
         "CREATE TABLE t028_dup(a SMALLINT PRIMARY KEY)",
         "INSERT INTO t028_dup(a) VALUES (1)",
         """CREATE PROCEDURE t028_h_es()
            DETERMINISTIC
         BEGIN
           DECLARE CONTINUE HANDLER FOR 1062
             SELECT 'Outer (bad)' AS 'h_es';
           BEGIN
             DECLARE CONTINUE HANDLER FOR SQLSTATE '23000'
               SELECT 'Inner (good)' AS 'h_es';
             INSERT INTO t028_dup VALUES (1);
           END;
         END""")

    # Streaming (SSCursor) reads every packet: if the trailing OK claimed
    # "more results exist", nextset() would block forever waiting for a
    # second result set.
    with cluster.mysql(dbname="public") as conn:
        cur = conn.cursor(pymysql.cursors.SSCursor)
        cur.execute("CALL t028_h_es()")
        rows = cur.fetchall()
        assert rows == [("Inner (good)",)], \
            "inner handler result set not streamed: %r" % (rows,)
        sets = 0
        while cur.nextset():
            sets += 1
            assert sets < 4, "unbounded result-set loop on CALL response"
        assert sets >= 1, "trailing CALL completion missing from response"
        cur.close()

        # The same connection must still be fully usable afterwards.
        with conn.cursor() as cur:
            cur.execute("SELECT 42")
            assert cur.fetchone() == (42,)

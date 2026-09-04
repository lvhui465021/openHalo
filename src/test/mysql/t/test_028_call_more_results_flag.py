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

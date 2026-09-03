"""MySQL 5.7 [NOT] DETERMINISTIC is valid on CREATE PROCEDURE too, not just
CREATE FUNCTION.

MySQL 5.7 Reference Manual 13.1.16 (Routine Characteristics) lists
[NOT] DETERMINISTIC as a characteristic of both CREATE PROCEDURE and CREATE
FUNCTION. plmysql maps it to a PostgreSQL volatility DefElem (STABLE for
DETERMINISTIC, VOLATILE for NOT DETERMINISTIC), which is correct for
functions but was passed straight through to PostgreSQL's native
CreateFunction machinery for procedures too -- and PostgreSQL's own
compute_common_attribute() (functioncmds.c) unconditionally rejects a
volatility attribute on a procedure ("invalid attribute in procedure
definition", errno 1105), since a real PostgreSQL procedure has no such
concept. This was the second-largest compatibility gap found by replaying
MySQL's own sp.test/trigger.test regression SQL (20 CREATE PROCEDURE
failures, all of this exact shape).

MySQL's own DETERMINISTIC characteristic is purely advisory for a
PROCEDURE (it has no runtime effect there -- only a FUNCTION's result can be
cached/reused based on it), so the fix silently drops the volatility option
when building a PROCEDURE and leaves it untouched for FUNCTION, where the
existing STABLE/VOLATILE mapping is correct and must keep working.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _provolatile(cluster, proname):
    out = cluster.psql(
        "SELECT provolatile FROM pg_proc WHERE proname='%s';" % proname)
    return out.strip()


def run(cluster):
    # DETERMINISTIC / NOT DETERMINISTIC on a PROCEDURE must compile and run.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t025_det_proc",
         "CREATE PROCEDURE t025_det_proc() DETERMINISTIC "
         "BEGIN SET @t025 = 1; END",
         "DROP PROCEDURE IF EXISTS t025_notdet_proc",
         "CREATE PROCEDURE t025_notdet_proc() NOT DETERMINISTIC "
         "BEGIN SET @t025 = 2; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t025_det_proc()")
            cur.fetchall()
            cur.execute("CALL t025_notdet_proc()")
            cur.fetchall()

    # A single-statement (BEGIN-less) PROCEDURE body with DETERMINISTIC must
    # also work -- this exercises both fixes (A1 + A2) together, matching
    # the shape most of MySQL's own regression failures actually had.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t025_det_oneliner",
         "CREATE PROCEDURE t025_det_oneliner(OUT x INT) "
         "DETERMINISTIC SET x = 7")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t025_det_oneliner(@t025_out)")
            cur.fetchall()
            cur.execute("SELECT @t025_out")
            # MySQL user variables round-trip loosely typed; accept either.
            assert cur.fetchone() in ((7,), ('7',))

    # Regression: FUNCTION must keep the real STABLE/VOLATILE mapping.
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t025_det_func",
         "CREATE FUNCTION t025_det_func() RETURNS INT "
         "DETERMINISTIC BEGIN RETURN 1; END",
         "DROP FUNCTION IF EXISTS t025_notdet_func",
         "CREATE FUNCTION t025_notdet_func() RETURNS INT "
         "NOT DETERMINISTIC BEGIN RETURN 1; END")
    assert _provolatile(cluster, "t025_det_func") == "s", \
        "DETERMINISTIC must still map FUNCTION volatility to STABLE"
    assert _provolatile(cluster, "t025_notdet_func") == "v", \
        "NOT DETERMINISTIC must still map FUNCTION volatility to VOLATILE"

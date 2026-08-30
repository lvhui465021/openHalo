"""Routine sql_mode snapshots must drive execution, not just metadata.

The adapter already has non-strict coercion paths (for example assigning an
empty string to an integer yields zero).  A routine's CREATE-time sql_mode is
stored in pg_proc.proconfig, so the PL/MySQL handler must temporarily apply
that snapshot while executing the body, including nested CALLs.
"""

import pymysql


def _scalar(cursor, sql):
    cursor.execute(sql)
    return cursor.fetchone()


def _expect_error(cursor, sql):
    try:
        cursor.execute(sql)
    except pymysql.MySQLError:
        return
    raise AssertionError("expected sql_mode-sensitive statement to fail: %s" % sql)


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SET SESSION sql_mode = ''")
            cur.execute("DROP PROCEDURE IF EXISTS t019_relaxed")
            cur.execute("""CREATE PROCEDURE t019_relaxed()
                        BEGIN
                            DECLARE v INT;
                            SET v = '';
                            SET @t019_relaxed = v;
                        END""")

            cur.execute("SET SESSION sql_mode = 'STRICT_TRANS_TABLES'")
            cur.execute("DROP PROCEDURE IF EXISTS t019_strict")
            cur.execute("""CREATE PROCEDURE t019_strict()
                        BEGIN
                            DECLARE v INT;
                            SET v = '';
                        END""")

            # Nested routine calls must restore the outer snapshot.  If the
            # inner relaxed CALL leaked its mode, the final assignment would
            # incorrectly succeed.
            cur.execute("DROP PROCEDURE IF EXISTS t019_nested")
            cur.execute("""CREATE PROCEDURE t019_nested()
                        BEGIN
                            DECLARE v INT;
                            CALL t019_relaxed();
                            SET v = '';
                        END""")

    # A strict routine must reject the conversion even with a non-strict
    # caller.  Each expected client-visible error gets a fresh connection:
    # the protocol adapter has a separate legacy result-packet issue after an
    # unhandled CALL error, unrelated to the routine's sql_mode semantics.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SET SESSION sql_mode = ''")
            _expect_error(cur, "CALL t019_strict()")

    # The same applies after an inner relaxed CALL returns: the outer strict
    # mode must be restored before its next statement executes.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SET SESSION sql_mode = ''")
            _expect_error(cur, "CALL t019_nested()")

    # Conversely, a relaxed routine overrides a strict caller only for its
    # body; once it returns, the strict caller is active again.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SET SESSION sql_mode = 'STRICT_ALL_TABLES'")
            cur.execute("CALL t019_relaxed()")
            assert _scalar(cur, "SELECT @t019_relaxed") == ("0",), \
                "routine did not use its own relaxed snapshot"
            _expect_error(cur, "SELECT CAST('' AS SIGNED)")

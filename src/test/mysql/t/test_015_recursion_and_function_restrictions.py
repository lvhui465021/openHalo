"""MySQL 5.7 stored-routine recursion and function result-set restrictions.

MySQL permits recursive PROCEDURE calls only up to the session's
max_sp_recursion_depth (whose default, zero, disables recursion), while
recursive FUNCTION calls are never permitted.  A stored function must also
not return an ad-hoc result set.
"""

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _expect_errno(cursor, sql, errno):
    try:
        cursor.execute(sql)
    except pymysql.MySQLError as exc:
        assert exc.args[0] == errno, exc
    else:
        raise AssertionError("expected MySQL errno %d for %s" % (errno, sql))


def run(cluster):
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t015_proc",
         """CREATE PROCEDURE t015_proc(IN n INT)
         BEGIN
             IF n > 0 THEN
                 CALL t015_proc(n - 1);
             END IF;
         END""")

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            # MySQL 5.7's default disables recursive procedure calls.
            cur.execute("SET SESSION max_sp_recursion_depth = 0")
            _expect_errno(cur, "CALL t015_proc(1)", 1456)

            # A value of one permits one recursive re-entry but rejects the
            # second one for the same procedure.
            cur.execute("SET SESSION max_sp_recursion_depth = 1")
            cur.execute("CALL t015_proc(1)")
            _expect_errno(cur, "CALL t015_proc(2)", 1456)

            # MySQL 5.7 restricts the variable itself to 0..255.  The
            # adapter's generic validation error need not have a particular
            # errno, but it must reject the SET and preserve the old value.
            try:
                cur.execute("SET SESSION max_sp_recursion_depth = 256")
            except pymysql.MySQLError:
                pass
            else:
                raise AssertionError("max_sp_recursion_depth accepted 256")
            cur.execute("SELECT @@session.max_sp_recursion_depth")
            assert cur.fetchone() == ("1",)

    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t015_func",
         """CREATE FUNCTION t015_func(n INT) RETURNS INT
         BEGIN
             IF n = 0 THEN
                 RETURN 0;
             END IF;
             RETURN t015_func(n - 1);
         END""",
         "DROP FUNCTION IF EXISTS t015_resultset",
         """CREATE FUNCTION t015_resultset() RETURNS INT
         BEGIN
             SELECT 1;
             RETURN 1;
         END""")

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            _expect_errno(cur, "SELECT t015_func(1)", 1424)
            _expect_errno(cur, "SELECT t015_resultset()", 1415)

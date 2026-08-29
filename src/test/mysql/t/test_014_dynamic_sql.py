"""Gap check: MySQL 5.7 dynamic SQL is PREPARE/EXECUTE/DEALLOCATE PREPARE
(https://dev.mysql.com/doc/refman/5.7/en/sql-prepared-statements.html) --
a named, session-scoped prepared statement built from a string literal or
user variable, run with EXECUTE ... USING @vars, and explicitly freed.
Usable in stored PROCEDUREs (not functions/triggers).

mys_gram.y already has PrepareStmt/ExecuteStmt/DeallocateStmt productions
that look MySQL-shaped (PREPARE name FROM Sconst|@uservar; EXECUTE name
[USING expr_list]; DEALLOCATE PREPARE name) -- this checks whether that
machinery actually works end-to-end over the MySQL protocol, both as a
plain top-level statement sequence and, more importantly, from inside a
stored procedure body (which is what MySQL callers actually need, and
where plmysql's own leftover plpgsql-style K_EXECUTE grammar could get in
the way instead).
"""
import pymysql


CONN = None


def _ddl(cluster, *statements):
    global CONN
    if CONN is None:
        CONN = cluster.mysql(dbname="public")
    with CONN.cursor() as cur:
        for sql in statements:
            cur.execute(sql)


def _scalar(cluster, sql):
    global CONN
    if CONN is None:
        CONN = cluster.mysql(dbname="public")
    with CONN.cursor() as cur:
        cur.execute(sql)
        return cur.fetchone()


def run(cluster):
    # ------------------------------------------------- top-level, from a string literal
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("PREPARE t014_s1 FROM 'SELECT 1 + 1'")
            cur.execute("EXECUTE t014_s1")
            assert cur.fetchone() == (2,), "top-level PREPARE FROM string literal failed"
            cur.execute("DEALLOCATE PREPARE t014_s1")

    # ------------------------------------------------- top-level, from a user variable, with USING
    _ddl(cluster,
         "DROP TABLE IF EXISTS t014_t",
         "CREATE TABLE t014_t(v INT)",
         "INSERT INTO t014_t VALUES (10)",
         "SET @t014_sql = 'UPDATE t014_t SET v = v + ? WHERE v = ?'",
         "PREPARE t014_s2 FROM @t014_sql",
         "SET @t014_a = 5, @t014_b = 10",
         "EXECUTE t014_s2 USING @t014_a, @t014_b",
         "DEALLOCATE PREPARE t014_s2")
    assert _scalar(cluster, "SELECT v FROM t014_t") == (15,), \
        "top-level PREPARE FROM @uservar + EXECUTE USING failed"

    # ------------------------------------------------- inside a stored PROCEDURE body
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t014_p",
         """CREATE PROCEDURE t014_p(IN tbl VARCHAR(64))
         BEGIN
             SET @t014_dyn = CONCAT('SELECT COUNT(*) FROM ', tbl);
             PREPARE t014_s3 FROM @t014_dyn;
             EXECUTE t014_s3;
             DEALLOCATE PREPARE t014_s3;
         END""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t014_p('t014_t')")
            assert cur.fetchone() == (1,), \
                "PREPARE/EXECUTE/DEALLOCATE PREPARE inside a procedure body failed"

    # MySQL permits named prepared statements in PROCEDUREs only.  Reject the
    # definition itself in FUNCTION context, before a session-scoped prepared
    # statement can leak out of the function invocation.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP FUNCTION IF EXISTS t014_f")
            try:
                cur.execute("""CREATE FUNCTION t014_f() RETURNS INT
                    BEGIN
                        PREPARE t014_bad FROM 'SELECT 1';
                        RETURN 1;
                    END""")
            except pymysql.MySQLError as exc:
                assert exc.args[0] == 1336, exc
            else:
                raise AssertionError("PREPARE was accepted in a stored function")

    CONN.close()

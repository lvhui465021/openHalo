"""Gap check: MySQL 5.7 lets a PROCEDURE (not FUNCTION) return an ad-hoc
result set to the caller via a bare SELECT with no INTO clause -- this is
one of the most common stored-procedure patterns
(https://dev.mysql.com/doc/refman/5.7/en/call.html: "stored procedures ...
can also produce result sets"). M1's plan intentionally blocked all bare
SELECTs ("query has no destination for result data") and deferred lifting
it for procedures to M5, but M5 only shipped OUT/INOUT writeback -- this
test finds out whether the bare-SELECT restriction was ever revisited.
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


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t013_t",
         "CREATE TABLE t013_t(v INT)",
         "INSERT INTO t013_t VALUES (1), (2), (3)",
         "DROP PROCEDURE IF EXISTS t013_p",
         """CREATE PROCEDURE t013_p()
         BEGIN
             SELECT v FROM t013_t ORDER BY v;
         END""")

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t013_p()")
            rows = cur.fetchall()
            assert rows == ((1,), (2,), (3,)), \
                "expected the bare SELECT's result set back from CALL, got %r" % (rows,)

    CONN.close()

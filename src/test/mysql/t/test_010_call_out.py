"""M5: CALL writes OUT/INOUT arguments back into the caller's @variables
and produces no result set of its own (MySQL semantics).
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
    # ---------------------------------------------------- OUT/INOUT writeback
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t010_out",
         """CREATE PROCEDURE t010_out(OUT x INT, INOUT y INT)
         BEGIN
             SET x = y * 10;
             SET y = y + 1;
         END""")
    _ddl(cluster, "SET @a = 0, @b = 7", "CALL t010_out(@a, @b)")
    _rows = _scalar(cluster, "SELECT @a, @b")
    assert _rows == ("70", "8"), "got %r" % (_rows,)

    # text values round-trip too
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t010_txt",
         """CREATE PROCEDURE t010_txt(OUT s TEXT)
         BEGIN
             SET s = 'done';
         END""")
    _ddl(cluster, "SET @t = ''", "CALL t010_txt(@t)")
    assert _scalar(cluster, "SELECT @t") == ("done",)

    # a procedure with no OUT args still works
    _ddl(cluster,
         "DROP TABLE IF EXISTS t010_t",
         "CREATE TABLE t010_t(v INT)",
         "DROP PROCEDURE IF EXISTS t010_in",
         """CREATE PROCEDURE t010_in(IN n INT)
         BEGIN
             INSERT INTO t010_t VALUES (n);
         END""")
    _ddl(cluster, "CALL t010_in(5)")
    assert _scalar(cluster, "SELECT v FROM t010_t") == (5,)

    # CALL produces no result set of its own
    _ddl(cluster, "SET @a = 0")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t010_out(@a, @a)")
            assert cur.description is None or cur.fetchall() in ([],), \
                "CALL leaked a result set to the client"

    # mixed IN / OUT / INOUT argument order
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t010_mix",
         """CREATE PROCEDURE t010_mix(IN a INT, OUT b INT, INOUT c INT)
         BEGIN
             SET b = a * 2;
             SET c = c + b;
         END""")
    _ddl(cluster, "SET @p = 1, @q = 10", "CALL t010_mix(3, @p, @q)")
    assert _scalar(cluster, "SELECT @p, @q") == ("6", "16")

    CONN.close()

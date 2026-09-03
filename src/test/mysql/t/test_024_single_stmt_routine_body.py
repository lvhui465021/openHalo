"""MySQL 5.7 CREATE PROCEDURE/FUNCTION without BEGIN...END (a single statement).

MySQL 5.7 Reference Manual 13.6.1: "If the routine contains no compound
statements, you can omit the BEGIN ... END block." plmysql's routine-body
grammar (mysql_routine_body in mys_gram.y) previously required a literal
BEGIN as the first token, so e.g. "CREATE PROCEDURE p() INSERT INTO t
VALUES (1)" failed with a syntax error -- this was, by count, the single
largest compatibility gap found by replaying MySQL's own sp.test/trigger.test
regression SQL against openHalo (~112 of ~460 CREATE PROCEDURE/FUNCTION
failures across those two files were exactly this shape).

The fix adds a second mysql_routine_body alternative keyed on the realistic
set of MySQL single-statement leading keywords (SELECT/INSERT/UPDATE/DELETE/
REPLACE/CALL/SET); DECLARE/HANDLER/flow control are intentionally excluded
since MySQL itself requires a BEGIN block for those. The captured text is
wrapped in "BEGIN ...; END" before being handed to plmysql, since plmysql's
own compiler (pl_gram.y) requires every routine body to be a pl_block.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t024_t",
         "CREATE TABLE t024_t (id CHAR(16), data INT)")

    # Each of the supported leading keywords must compile as a bare,
    # BEGIN-less routine body.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t024_ins",
         "CREATE PROCEDURE t024_ins(x CHAR(16), y INT) "
         "INSERT INTO t024_t VALUES (x, y)",
         "DROP PROCEDURE IF EXISTS t024_upd",
         "CREATE PROCEDURE t024_upd() UPDATE t024_t SET data = data + 1",
         "DROP PROCEDURE IF EXISTS t024_del",
         "CREATE PROCEDURE t024_del(x CHAR(16)) "
         "DELETE FROM t024_t WHERE id = x",
         "DROP PROCEDURE IF EXISTS t024_sel",
         "CREATE PROCEDURE t024_sel() SELECT * FROM t024_t",
         "DROP PROCEDURE IF EXISTS t024_set",
         "CREATE PROCEDURE t024_set(OUT x INT) SET x = 99",
         "DROP PROCEDURE IF EXISTS t024_call",
         "CREATE PROCEDURE t024_call(x CHAR(16), y INT) "
         "CALL t024_ins(x, y)")

    # Execute, not just compile: confirm plmysql's own compiler accepted the
    # BEGIN...END-wrapped body and the statement really runs.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t024_ins('a', 1)")
            cur.fetchall()
            cur.execute("SELECT * FROM t024_t WHERE id='a'")
            rows = cur.fetchall()
            assert rows == (('a', 1),), rows

            # a single-statement body that itself CALLs another routine
            cur.execute("CALL t024_call('b', 2)")
            cur.fetchall()
            cur.execute("SELECT * FROM t024_t WHERE id='b'")
            rows = cur.fetchall()
            assert rows == (('b', 2),), rows

            cur.execute("CALL t024_upd()")
            cur.fetchall()
            cur.execute("SELECT data FROM t024_t WHERE id='a'")
            assert cur.fetchall() == ((2,),)

            cur.execute("CALL t024_del('b')")
            cur.fetchall()
            cur.execute("SELECT * FROM t024_t WHERE id='b'")
            assert cur.fetchall() == tuple()

    # Regression: the compound BEGIN...END form and the FUNCTION "RETURN
    # expr" one-liner (an existing, different single-statement mechanism)
    # must still both work unchanged.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t024_begin",
         "CREATE PROCEDURE t024_begin() "
         "BEGIN INSERT INTO t024_t VALUES ('c', 3); END",
         "DROP FUNCTION IF EXISTS t024_return",
         "CREATE FUNCTION t024_return() RETURNS INT RETURN 42")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t024_return()")
            assert cur.fetchone() == (42,)

"""M3 cursors: DECLARE CURSOR / OPEN / FETCH [FROM] INTO / CLOSE, plus the
column-first name resolution MySQL uses inside embedded SQL.

Also spot-checks that a bare SELECT inside a routine streams its result set
to the client (M5; see test_003's _bare_select_returns_resultset for the
dedicated test).
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _scalar(cluster, sql):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchone()


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t008_t",
         "CREATE TABLE t008_t(v INT)",
         "INSERT INTO t008_t VALUES (10),(20),(30)")

    # ------------------------------------------------- classic cursor walk
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t008_sum",
         """CREATE PROCEDURE t008_sum()
         BEGIN
             DECLARE total INT DEFAULT 0;
             DECLARE v INT;
             DECLARE done INT DEFAULT 0;
             DECLARE cur CURSOR FOR SELECT v FROM t008_t;
             OPEN cur;
             <<lp>> LOOP
                 FETCH cur INTO v;
                 IF done = 1 THEN LEAVE lp; END IF;
                 SET total = total + v;
             END LOOP lp;
             CLOSE cur;
             INSERT INTO t008_t VALUES (total);
         END""")
    # (the NOT FOUND handler variant lives in test_009; this one uses the
    # pre-M4 NULL check so the cursor mechanics stay isolated)
    _ddl(cluster, "DROP PROCEDURE IF EXISTS t008_sum2")
    _ddl(cluster, """CREATE PROCEDURE t008_sum2()
         BEGIN
             DECLARE total INT DEFAULT 0;
             DECLARE v INT;
             DECLARE cur CURSOR FOR SELECT v FROM t008_t;
             OPEN cur;
             <<lp>> LOOP
                 FETCH cur INTO v;
                 IF v IS NULL THEN LEAVE lp; END IF;
                 SET total = total + v;
             END LOOP lp;
             CLOSE cur;
             INSERT INTO t008_t VALUES (total);
         END""")
    _ddl(cluster, "CALL t008_sum2()")
    assert _scalar(cluster, "SELECT max(v) FROM t008_t") == (60,)

    # FETCH FROM variant + column-first resolution: the cursor query's v is
    # the TABLE column, not the local variable of the same name.
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t008_cnt",
         """CREATE FUNCTION t008_cnt() RETURNS INT
         BEGIN
             DECLARE n INT DEFAULT 0;
             DECLARE v INT;
             DECLARE cur CURSOR FOR SELECT v FROM t008_t;
             OPEN cur;
             <<lp>> LOOP
                 FETCH FROM cur INTO v;
                 IF v IS NULL THEN LEAVE lp; END IF;
                 SET n = n + 1;
             END LOOP lp;
             CLOSE cur;
             RETURN n;
         END""")
    # the table currently holds 10,20,30,60 -> 4 rows
    assert _scalar(cluster, "SELECT t008_cnt()") == (4,)

    # variable fallback: no such column, so the local variable is read
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t008_fb",
         """CREATE FUNCTION t008_fb() RETURNS INT
         BEGIN
             DECLARE myvar INT DEFAULT 77;
             DECLARE got INT;
             DECLARE cur CURSOR FOR
                 SELECT myvar FROM (SELECT 1 AS x) z;
             OPEN cur;
             FETCH cur INTO got;
             CLOSE cur;
             RETURN got;
         END""")
    assert _scalar(cluster, "SELECT t008_fb()") == (77,)

    # multiple cursors in one routine
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t008_two",
         """CREATE FUNCTION t008_two() RETURNS INT
         BEGIN
             DECLARE a INT; DECLARE b INT;
             DECLARE c1 CURSOR FOR SELECT max(v) FROM t008_t;
             DECLARE c2 CURSOR FOR SELECT min(v) FROM t008_t;
             OPEN c1; FETCH c1 INTO a; CLOSE c1;
             OPEN c2; FETCH c2 INTO b; CLOSE c2;
             RETURN a - b;
         END""")
    assert _scalar(cluster, "SELECT t008_two()") == (50,)

    # bare SELECT in a routine streams its result set to the client (M5;
    # see test_003's _bare_select_returns_resultset for the dedicated test)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t008_baresel",
         "CREATE PROCEDURE t008_baresel() BEGIN SELECT 55; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t008_baresel()")
            assert cur.fetchall() == ((55,),), \
                "expected the bare SELECT's row back from CALL"

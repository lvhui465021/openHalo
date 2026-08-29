"""M2 flow control: WHILE/REPEAT/LOOP + LEAVE/ITERATE, CASE (both forms),
multi-target SET, SELECT INTO, IN parameters, nested calls, NULL handling.

Known limitation pinned here: MySQL's \"label:\" loop-label prefix is not
supported (see pl_gram.y); loop labels use the <<label>> spelling.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _scalar(cluster, sql, args=None):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchone()


def run(cluster):
    _ddl(cluster, "DROP TABLE IF EXISTS t007_t", "CREATE TABLE t007_t(v INT)")

    # ------------------------------------------------------------ WHILE..DO
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t007_while",
         """CREATE PROCEDURE t007_while()
         BEGIN
             DECLARE i INT DEFAULT 0;
             WHILE i < 5 DO
                 INSERT INTO t007_t VALUES (i);
                 SET i = i + 1;
             END WHILE;
         END""")
    _ddl(cluster, "CALL t007_while()")
    assert _scalar(cluster, "SELECT count(*), sum(v) FROM t007_t") == (5, 10)

    # WHILE with a parenthesised / function-call condition
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_wfun",
         """CREATE FUNCTION t007_wfun() RETURNS INT
         BEGIN
             DECLARE i INT DEFAULT 0;
             WHILE IF(i < 2, 1, 0) = 1 DO
                 SET i = i + 1;
             END WHILE;
             RETURN i;
         END""")
    assert _scalar(cluster, "SELECT t007_wfun()") == (2,)

    # ------------------------------------------------------- REPEAT..UNTIL
    _ddl(cluster, "DELETE FROM t007_t",
         "DROP PROCEDURE IF EXISTS t007_repeat",
         """CREATE PROCEDURE t007_repeat()
         BEGIN
             DECLARE i INT DEFAULT 0;
             REPEAT
                 INSERT INTO t007_t VALUES (i);
                 SET i = i + 1;
             UNTIL i >= 3 END REPEAT;
         END""")
    _ddl(cluster, "CALL t007_repeat()")
    assert _scalar(cluster, "SELECT sum(v) FROM t007_t") == (3,)

    # REPEAT whose body contains a REPEAT() function call
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_rfun",
         """CREATE FUNCTION t007_rfun() RETURNS TEXT
         BEGIN
             DECLARE s TEXT DEFAULT '';
             REPEAT
                 SET s = concat(s, REPEAT('a', 2));
             UNTIL length(s) >= 4 END REPEAT;
             RETURN s;
         END""")
    assert _scalar(cluster, "SELECT t007_rfun()") == ("aaaa",)

    # -------------------------------------------- LOOP + LEAVE + ITERATE
    _ddl(cluster, "DELETE FROM t007_t",
         "DROP PROCEDURE IF EXISTS t007_loop",
         """CREATE PROCEDURE t007_loop()
         BEGIN
             DECLARE i INT DEFAULT 0;
             <<outer_loop>>
             LOOP
                 SET i = i + 1;
                 IF i % 2 = 0 THEN
                     ITERATE outer_loop;
                 END IF;
                 IF i > 7 THEN
                     LEAVE outer_loop;
                 END IF;
                 INSERT INTO t007_t VALUES (i);
             END LOOP outer_loop;
         END""")
    _ddl(cluster, "CALL t007_loop()")
    assert _scalar(cluster, "SELECT sum(v) FROM t007_t") == (16,)  # 1+3+5+7

    # LEAVE out of a labelled BEGIN block
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_lbl",
         """CREATE FUNCTION t007_lbl() RETURNS INT
         BEGIN
             DECLARE r INT DEFAULT 0;
             <<blk>> BEGIN
                 SET r = 5;
                 LEAVE blk;
                 SET r = 99;
             END blk;
             RETURN r;
         END""")
    assert _scalar(cluster, "SELECT t007_lbl()") == (5,)

    # ------------------------------------------------- CASE (both forms)
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_case1",
         """CREATE FUNCTION t007_case1(n INT) RETURNS TEXT
         BEGIN
             DECLARE r TEXT;
             CASE n
                 WHEN 1 THEN SET r = 'one';
                 WHEN 2 THEN SET r = 'two';
                 ELSE SET r = 'many';
             END CASE;
             RETURN r;
         END""")
    for arg, want in ((1, "one"), (2, "two"), (3, "many")):
        assert _scalar(cluster, "SELECT t007_case1(%d)" % arg) == (want,), arg

    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_case2",
         """CREATE FUNCTION t007_case2(n INT) RETURNS TEXT
         BEGIN
             DECLARE r TEXT;
             CASE
                 WHEN n < 10 THEN SET r = 'small';
                 ELSE SET r = 'big';
             END CASE;
             RETURN r;
         END""")
    assert _scalar(cluster, "SELECT t007_case2(50)") == ("big",)

    # ----------------------------------------------------- multi-target SET
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_mset",
         """CREATE FUNCTION t007_mset() RETURNS INT
         BEGIN
             DECLARE a INT DEFAULT 1;
             DECLARE b INT DEFAULT 2;
             DECLARE c TEXT DEFAULT 'x';
             SET a = 10, b = a + 1, c = 'y';
             RETURN a * 100 + b * 10 + IF(c = 'y', 1, 0);
         END""")
    assert _scalar(cluster, "SELECT t007_mset()") == (1111,)

    # ------------------------------------------------- SELECT ... INTO var
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t007_into",
         """CREATE PROCEDURE t007_into()
         BEGIN
             DECLARE v INT;
             SELECT max(v) INTO v FROM t007_t;
             INSERT INTO t007_t VALUES (v + 100);
         END""")
    _ddl(cluster, "CALL t007_into()")
    assert _scalar(cluster, "SELECT max(v) FROM t007_t") == (107,)

    # ------------------------------------------------------ IN parameters
    _ddl(cluster, "DELETE FROM t007_t",
         "DROP PROCEDURE IF EXISTS t007_arg",
         """CREATE PROCEDURE t007_arg(IN n INT)
         BEGIN
             INSERT INTO t007_t VALUES (n + 1);
         END""")
    _ddl(cluster, "CALL t007_arg(41)")
    assert _scalar(cluster, "SELECT v FROM t007_t") == (42,)

    # ------------------------------------------- nested routine invocation
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_inner",
         """CREATE FUNCTION t007_inner(n INT) RETURNS INT
         BEGIN RETURN n * 2; END""",
         "DROP FUNCTION IF EXISTS t007_outer",
         """CREATE FUNCTION t007_outer(n INT) RETURNS INT
         BEGIN
             DECLARE r INT;
             SET r = t007_inner(n) + 1;
             RETURN r;
         END""")
    assert _scalar(cluster, "SELECT t007_outer(20)") == (41,)

    # ------------------------------------------------------- NULL handling
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t007_null",
         """CREATE FUNCTION t007_null() RETURNS INT
         BEGIN
             DECLARE v INT;
             RETURN v;
         END""")
    assert _scalar(cluster, "SELECT t007_null()") == (None,)

    # ---------------------------------------------------- SHOW CREATE output
    _ddl(cluster, "DROP PROCEDURE IF EXISTS t007_show",
         "CREATE PROCEDURE t007_show() BEGIN DECLARE x INT DEFAULT 1; END")
    row = _scalar(cluster, "SHOW CREATE PROCEDURE t007_show")
    assert "CREATE" in row[2] and "t007_show" in row[2], row

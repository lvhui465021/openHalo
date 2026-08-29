"""M4 condition handling: DECLARE CONTINUE/EXIT HANDLER, condition names,
SIGNAL/RESIGNAL, GET DIAGNOSTICS, errno handling, DECLARE ordering,
statement-level atomicity under CONTINUE handlers.
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


def _all(cluster, sql):
    global CONN
    if CONN is None:
        CONN = cluster.mysql(dbname="public")
    with CONN.cursor() as cur:
        cur.execute(sql)
        return cur.fetchall()


def _expect_error(cluster, sql, errno=None, fragment=None):
    try:
        _ddl(cluster, sql)
    except pymysql.err.MySQLError as e:
        if errno is not None:
            assert e.args[0] == errno, \
                "expected errno %d, got %r" % (errno, e)
        if fragment is not None:
            assert fragment in str(e), \
                "expected %r in %r" % (fragment, str(e))
    else:
        raise AssertionError("expected this to fail: %s" % sql[:80])


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t009_t",
         "CREATE TABLE t009_t(v INT)",
         "INSERT INTO t009_t VALUES (10),(20),(30)")

    # ---------------------------------- classic NOT FOUND cursor loop (M4)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_cur",
         """CREATE PROCEDURE t009_cur()
         BEGIN
             DECLARE total INT DEFAULT 0;
             DECLARE v INT;
             DECLARE done INT DEFAULT 0;
             DECLARE cur CURSOR FOR SELECT v FROM t009_t;
             DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
             OPEN cur;
             <<lp>> LOOP
                 FETCH cur INTO v;
                 IF done = 1 THEN LEAVE lp; END IF;
                 SET total = total + v;
             END LOOP lp;
             CLOSE cur;
             INSERT INTO t009_t VALUES (total);
         END""")
    _ddl(cluster, "CALL t009_cur()")
    assert _scalar(cluster, "SELECT max(v) FROM t009_t") == (60,)

    # --------------------------------------------------------- EXIT handler
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t009_exit",
         """CREATE FUNCTION t009_exit() RETURNS INT
         BEGIN
             DECLARE r INT DEFAULT 0;
             BEGIN
                 DECLARE EXIT HANDLER FOR SQLEXCEPTION SET r = -1;
                 SET r = 1;
                 INSERT INTO t009_nosuch VALUES (1);
                 SET r = 2;
             END;
             RETURN r;
         END""")
    assert _scalar(cluster, "SELECT t009_exit()") == (-1,)

    # ------------------------------------- statement-level atomicity under
    # CONTINUE: each failed statement is rolled back alone, prior successful
    # statements keep their effects, execution resumes after the failure.
    _ddl(cluster,
         "DROP TABLE IF EXISTS t009_dup",
         "CREATE TABLE t009_dup(id INT PRIMARY KEY, v INT)",
         "INSERT INTO t009_dup VALUES (1, 100)",
         "DROP PROCEDURE IF EXISTS t009_duph",
         """CREATE PROCEDURE t009_duph()
         BEGIN
             DECLARE v INT DEFAULT 0;
             DECLARE CONTINUE HANDLER FOR 1062 SET v = v + 1;
             INSERT INTO t009_dup VALUES (1, 1);
             INSERT INTO t009_dup VALUES (2, 2);
             INSERT INTO t009_dup VALUES (1, 3);
             INSERT INTO t009_dup VALUES (2, 9);
         END""")
    _ddl(cluster, "CALL t009_duph()")
    _rows = _all(cluster, "SELECT id, v FROM t009_dup ORDER BY id")
    assert _rows == ((1, 100), (2, 2)), "got %r" % (_rows,)

    # ----------------------------------------------- SIGNAL with MYSQL_ERRNO
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_sig",
         """CREATE PROCEDURE t009_sig()
         BEGIN
             SIGNAL SQLSTATE '45000'
                 SET MESSAGE_TEXT = 'custom failure', MYSQL_ERRNO = 40001;
         END""")
    _expect_error(cluster, "CALL t009_sig()",
                  fragment="custom failure")

    # SIGNAL of a named condition declared by SQLSTATE
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_named",
         """CREATE PROCEDURE t009_named()
         BEGIN
             DECLARE boom CONDITION FOR SQLSTATE 'A0001';
             SIGNAL boom SET MESSAGE_TEXT = 'named boom';
         END""")
    _expect_error(cluster, "CALL t009_named()", fragment="named boom")

    # SIGNAL without MESSAGE_TEXT uses the MySQL default text
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_sig2",
         "CREATE PROCEDURE t009_sig2() BEGIN SIGNAL SQLSTATE '45000'; END")
    _expect_error(cluster, "CALL t009_sig2()",
                  fragment="Unhandled user-defined exception condition")

    # SQLSTATE round-trips to the client (mysqlclient stores it verbatim)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_state",
         "CREATE PROCEDURE t009_state() BEGIN SIGNAL SQLSTATE 'A0001'; END")
    try:
        _ddl(cluster, "CALL t009_state()")
    except pymysql.err.MySQLError as e:
        assert e.args[1].startswith("A0001") or \
            getattr(e, "sqlstate", "") == "A0001", repr(e)

    # ------------------------------------------------------- GET DIAGNOSTICS
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t009_diag",
         """CREATE FUNCTION t009_diag() RETURNS TEXT
         BEGIN
             DECLARE msg TEXT;
             DECLARE st CHAR(5);
             DECLARE eno INT;
             BEGIN
                 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                     GET DIAGNOSTICS CONDITION 1
                         msg = MESSAGE_TEXT,
                         st = RETURNED_SQLSTATE,
                         eno = MYSQL_ERRNO;
                 END;
                 INSERT INTO t009_nosuch VALUES (1);
             END;
             RETURN concat(st, '|', eno, '|', msg);
         END""")
    row = _scalar(cluster, "SELECT t009_diag()")
    st, eno, msg = row[0].split("|", 2)
    assert st == "42P01", st                      # undefined_table
    assert eno == "1146", eno                     # ER_NO_SUCH_TABLE
    assert "t009_nosuch" in msg, msg

    # GET CURRENT DIAGNOSTICS ... ROW_COUNT
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t009_rc",
         """CREATE FUNCTION t009_rc() RETURNS INT
         BEGIN
             DECLARE n INT;
             INSERT INTO t009_t VALUES (99);
             GET DIAGNOSTICS n = ROW_COUNT;
             RETURN n;
         END""")
    assert _scalar(cluster, "SELECT t009_rc()") == (1,)

    # ------------------------------------------------------------- RESIGNAL
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_res",
         """CREATE PROCEDURE t009_res()
         BEGIN
             BEGIN
                 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
                     RESIGNAL;
                 END;
                 SIGNAL SQLSTATE '45000'
                     SET MESSAGE_TEXT = 'original boom', MYSQL_ERRNO = 5555;
             END;
         END""")
    _expect_error(cluster, "CALL t009_res()",
                  fragment="original boom")

    # ------------------------------------- unhandled SQLEXCEPTION propagates
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_thr",
         """CREATE PROCEDURE t009_thr()
         BEGIN
             INSERT INTO t009_nosuch VALUES (1);
         END""")
    _expect_error(cluster, "CALL t009_thr()", errno=1146)

    # unhandled NOT FOUND is swallowed (MySQL default-handler semantics)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_swallow",
         """CREATE PROCEDURE t009_swallow()
         BEGIN
             DECLARE v INT;
             DECLARE cur CURSOR FOR SELECT v FROM t009_t;
             OPEN cur;
             FETCH cur INTO v;   -- ok
             FETCH cur INTO v;   -- NOT FOUND, swallowed: no handler, no abort
             CLOSE cur;
         END""")
    _ddl(cluster, "CALL t009_swallow()")

    # ---------------------------------------------- DECLARE ordering rules
    _expect_error(cluster,
                  """CREATE PROCEDURE t009_ord1()
                  BEGIN
                      DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
                      DECLARE v INT;
                  END""",
                  fragment="must be declared before")

    _expect_error(cluster,
                  """CREATE PROCEDURE t009_ord2()
                  BEGIN
                      DECLARE cur CURSOR FOR SELECT 1;
                      DECLARE v INT;
                  END""",
                  fragment="must be declared before")

    # conditions share phase 0 with variables and may interleave
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t009_ord3",
         """CREATE PROCEDURE t009_ord3()
         BEGIN
             DECLARE a INT DEFAULT 1;
             DECLARE e CONDITION FOR SQLSTATE 'A0001';
             DECLARE b INT DEFAULT 2;
             DECLARE cur CURSOR FOR SELECT 1;
             DECLARE CONTINUE HANDLER FOR NOT FOUND SET a = a;
             OPEN cur; CLOSE cur;
         END""")
    _ddl(cluster, "CALL t009_ord3()")

    # duplicate condition names within one block
    _expect_error(cluster,
                  """CREATE PROCEDURE t009_ord4()
                  BEGIN
                      DECLARE e CONDITION FOR SQLSTATE 'A0001';
                      DECLARE e CONDITION FOR SQLSTATE 'A0002';
                  END""",
                  fragment="duplicate declaration")

    CONN.close()

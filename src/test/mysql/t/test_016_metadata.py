"""M6 metadata: DEFINER account, sql_mode snapshot and timestamps recorded at
CREATE time; MySQL-native `label:` prefixes; new error-code mappings.

Before M6 the DEFINER clause was accepted and dropped, and the mysql.proc /
mys_informa_schema / SHOW CREATE surfaces returned a hard-coded definer
(owner@%), a fixed sql_mode string and fixed dates.  plmysql records
plmysql.definer / sql_mode / created / last_altered as routine metadata and
the metadata views read them back through mysql.get_plmysql_config().

That metadata is attached to the routine's OID as a "plmysql" security label
(SECURITY LABEL FOR plmysql ON FUNCTION/PROCEDURE ...) rather than in
pg_proc.proconfig: proconfig being non-empty makes PostgreSQL's
ExecuteCallStmt() force any CALL of the routine into an atomic execution
context, unconditionally blocking COMMIT/ROLLBACK in its body regardless of
SQL SECURITY -- this was the actual root cause of the compat report's C2 gap.
A MySQL trigger's own private underlying function is the one exception that
still uses proconfig (see mys_make_mysql_trigger_function(), mys_utility.c):
a trigger is never dispatched through CALL's atomic/non-atomic machinery, so
proconfig's side effect never applied to it, and test_017 asserts on that
storage directly.
"""

import pymysql


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


def _call(cluster, sql):
    """Execute without expecting a result row (CALL returns none)."""
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql)


def run(cluster):
    # ------------------------------------------------------ DEFINER storage
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t016_def",
         """CREATE DEFINER=`halo`@`localhost` PROCEDURE t016_def()
         BEGIN SET @t016 = 1; END""")
    out = cluster.psql(
        "SELECT label FROM pg_seclabel sl, pg_proc p "
        "WHERE sl.objoid = p.oid AND sl.classoid = 'pg_proc'::regclass "
        "AND sl.provider = 'plmysql' AND p.proname = 't016_def';")
    assert "plmysql.definer=halo@localhost" in out, \
        "DEFINER not recorded in the plmysql security label: %r" % out
    assert "plmysql.sql_mode=" in out, \
        "sql_mode snapshot not recorded: %r" % out
    assert "plmysql.created=" in out and "plmysql.last_altered=" in out, \
        "timestamps not recorded: %r" % out
    # Nothing of this must have leaked into proconfig -- that's the whole
    # point (see the module docstring): a non-empty proconfig would force
    # every CALL of this routine into PostgreSQL's atomic execution context.
    out = cluster.psql(
        "SELECT proconfig FROM pg_proc WHERE proname = 't016_def';")
    assert out.strip() == "", \
        "regular routine metadata must not use proconfig any more: %r" % out

    # sql_mode must still be live: executing the routine proves plmysql's
    # own handler correctly applies the label snapshot around the call
    # (plmysql_get_sql_mode_snapshot(), pl_handler.c).
    _call(cluster, "CALL t016_def()")

    row = cluster.psql(
        "SELECT rtrim(definer) FROM mysql.proc "
        "WHERE db = 'public' AND name = 't016_def';")
    assert row.strip() == "halo@localhost", "mysql.proc.definer: %r" % row

    row = cluster.psql(
        "SELECT rtrim(definer) FROM mys_informa_schema.procedures "
        "WHERE db = 'public' AND name = 't016_def';")
    assert row.strip() == "halo@localhost", \
        "mys_informa_schema.procedures.definer: %r" % row

    row = cluster.psql(
        "SELECT definer FROM mys_informa_schema.routines "
        "WHERE routine_name = 't016_def';")
    assert row.strip() == "halo@localhost", \
        "mys_informa_schema.routines.definer: %r" % row

    # SHOW CREATE renders the recorded DEFINER and the CREATE-time sql_mode.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SHOW CREATE PROCEDURE t016_def")
            r = cur.fetchone()
    assert r[0] == "t016_def", "SHOW CREATE name: %r" % (r,)
    assert r[1] == ("STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,"
                    "ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,"
                    "NO_ENGINE_SUBSTITUTION"), \
        "SHOW CREATE sql_mode must be the CREATE-time snapshot: %r" % (r[1],)
    assert r[2].startswith(
        "CREATE DEFINER=`halo`@`localhost` PROCEDURE `t016_def`("), \
        "SHOW CREATE must carry the recorded DEFINER: %r" % r[2]

    # A function with a multi-character host and the single-statement RETURN
    # form takes the same metadata path.
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t016_deffn",
         "CREATE DEFINER=`halo`@`%` FUNCTION t016_deffn() "
         "RETURNS INT RETURN 3")
    assert _scalar(cluster, "SELECT t016_deffn()") == (3,)
    out = cluster.psql(
        "SELECT label FROM pg_seclabel sl, pg_proc p "
        "WHERE sl.objoid = p.oid AND sl.classoid = 'pg_proc'::regclass "
        "AND sl.provider = 'plmysql' AND p.proname = 't016_deffn';")
    assert "plmysql.definer=halo@%" in out, "got %r" % out

    # Without DEFINER the views fall back to owner@%.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t016_noder",
         "CREATE PROCEDURE t016_noder() BEGIN SET @t016 = 2; END")
    row = cluster.psql(
        "SELECT rtrim(definer) FROM mysql.proc "
        "WHERE db = 'public' AND name = 't016_noder';")
    assert row.strip() == "halo@%", "no-DEFINER fallback: %r" % row

    # ------------------------------------------------------ sql_mode snapshot
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SET sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE'")
            cur.execute("""CREATE PROCEDURE t016_sm()
                           BEGIN SET @t016 = 3; END""")
            cur.execute("SELECT sql_mode FROM mysql.proc "
                        "WHERE db = 'public' AND name = 't016_sm'")
            assert cur.fetchone()[0].rstrip() == \
                "STRICT_TRANS_TABLES,NO_ZERO_DATE", \
                "mysql.proc.sql_mode must be the CREATE-time snapshot"
            # SHOW CREATE in the same session must not use the *current*
            # session mode either; a SHOW inside this same session (still set
            # to the custom mode) exercises exactly that.
            cur.execute("SHOW CREATE PROCEDURE t016_sm")
            r = cur.fetchone()
            assert r[1] == "STRICT_TRANS_TABLES,NO_ZERO_DATE", \
                "SHOW CREATE used the session mode instead of the snapshot: %r" % r[1]

    # ---------------------------------------------- created / last_altered
    row = cluster.psql(
        "SELECT created > '2025-01-01'::timestamptz FROM mysql.proc "
        "WHERE db = 'public' AND name = 't016_def';")
    assert row.strip() == "t", \
        "mysql.proc.created must be a real CREATE-time timestamp, got %r" % row

    # ---------------------------------------------- MySQL label: prefixes
    # CALL and the @t016 read must share one connection: @vars are
    # session-local.
    class _Call:
        def __init__(self, conn):
            self.cur = conn.cursor()

        def __enter__(self):
            return self

        def __exit__(self, *a):
            self.cur.close()

        def invoke(self, call_sql):
            self.cur.execute(call_sql)
            self.cur.execute("SELECT @t016")
            return self.cur.fetchone()

    def call_and_var(call_sql):
        with cluster.mysql(dbname="public") as conn:
            with _Call(conn) as c:
                return c.invoke(call_sql)

    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t016_lbl",
         """CREATE PROCEDURE t016_lbl()
         BEGIN
           DECLARE i INT DEFAULT 0;
           blk: BEGIN
             wl: WHILE i < 3 DO
               SET i = i + 1;
               IF i = 2 THEN ITERATE wl; END IF;
               IF i = 3 THEN LEAVE wl; END IF;
             END WHILE wl;
           END blk;
           SET @t016 = i;
         END""")
    assert call_and_var("CALL t016_lbl()") == ("3",), \
        "label: WHILE/LEAVE/ITERATE block did not compute @t016"

    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t016_lbl2",
         """CREATE PROCEDURE t016_lbl2()
         BEGIN
           DECLARE i INT DEFAULT 0;
           lp: LOOP
             SET i = i + 1;
             IF i = 5 THEN LEAVE lp; END IF;
           END LOOP lp;
           SET @t016 = i;
         END""")
    assert call_and_var("CALL t016_lbl2()") == ("5",)

    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t016_lbl3",
         """CREATE PROCEDURE t016_lbl3()
         BEGIN
           DECLARE i INT DEFAULT 3;
           rp: REPEAT
             SET i = i - 1;
           UNTIL i = 0
           END REPEAT rp;
           SET @t016 = i;
         END""")
    assert call_and_var("CALL t016_lbl3()") == ("0",), "REPEAT label: failed"

    # IF/ELSEIF parsing must be unaffected by the label: change
    # (K_ELSIF after a THEN body must still open an elseif branch).
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t016_elsif",
         """CREATE PROCEDURE t016_elsif()
         BEGIN
           DECLARE i INT DEFAULT 2;
           IF i = 1 THEN
             SET @t016 = 10;
           ELSEIF i = 2 THEN
             SET @t016 = 20;
           ELSE
             SET @t016 = 30;
           END IF;
         END""")
    assert call_and_var("CALL t016_elsif()") == ("20",), \
        "IF/ELSEIF regressed"

    # ------------------------------------------------- error-code mappings
    # 42701 duplicate column must now arrive as MySQL 1060 (previously the
    # unmapped fallback 1105).  pymysql picks the exception class from the
    # SQLSTATE, so catch both families.
    try:
        _ddl(cluster, "CREATE TABLE t016_dup(x INT, x INT)")
        raise AssertionError("duplicate column CREATE TABLE succeeded")
    except (pymysql.err.ProgrammingError, pymysql.err.OperationalError) as e:
        assert e.args[0] == 1060, \
            "duplicate column must map to 1060, got %r" % (e.args,)
        # The wire SQLSTATE is now MySQL-canonical (42S21), not PG's 42701.
        assert getattr(e, "sqlstate", None) == "42S21" or \
            "42S21" in e.args, \
            "duplicate column must carry canonical 42S21, got %r" % (e.args,)

    try:
        _ddl(cluster, "CREATE TABLE t016_dup2(x INT)",
             "CREATE TABLE t016_dup2(x INT)")
        raise AssertionError("duplicate table CREATE succeeded")
    except (pymysql.err.ProgrammingError, pymysql.err.OperationalError) as e:
        assert e.args[0] == 1050, \
            "duplicate table must map to 1050, got %r" % (e.args,)
        assert getattr(e, "sqlstate", None) == "42S01" or \
            "42S01" in e.args, \
            "duplicate table must carry canonical 42S01, got %r" % (e.args,)

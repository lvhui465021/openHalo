"""D-category: CREATE TRIGGER on a view or a temporary table.

MySQL 5.7 rejects both outright: ER_TRG_ON_VIEW_OR_TEMP_TABLE (1361),
"Trigger's '%s' is view or temporary table". The view case was already
being rejected by PostgreSQL's own native CreateTrigger() (a view has no
storage to fire a row-level trigger against), just with a generic errno
(1105) and PostgreSQL's own wording ("\"%s\" is a view") instead of
MySQL's. The temporary-table case was not rejected at all -- PostgreSQL
itself has no such restriction (temp tables support triggers just fine).

mys_check_mysql_trigger_target() (mys_utility.c) checks both explicitly,
before the native CREATE TRIGGER path runs, using MySQL's own errno and
message text for both.
"""

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    _ddl(cluster,
         "DROP VIEW IF EXISTS t032_v",
         "DROP TABLE IF EXISTS t032_base",
         "CREATE TABLE t032_base (id INT)",
         "CREATE VIEW t032_v AS SELECT * FROM t032_base")

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP TRIGGER IF EXISTS t032_on_view")
            try:
                cur.execute("CREATE TRIGGER t032_on_view BEFORE INSERT ON t032_v "
                            "FOR EACH ROW SET @t032 = 1")
                raise AssertionError(
                    "CREATE TRIGGER on a VIEW unexpectedly succeeded")
            except pymysql.err.OperationalError as e:
                assert e.args[0] == 1361, \
                    "expected 1361 (ER_TRG_ON_VIEW_OR_TEMP_TABLE), got %r" % (e.args,)
                assert "t032_v" in e.args[1], e.args

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS t032_tmp")
            cur.execute("CREATE TEMPORARY TABLE t032_tmp (id INT)")
            cur.execute("DROP TRIGGER IF EXISTS t032_on_tmp")
            try:
                cur.execute("CREATE TRIGGER t032_on_tmp BEFORE INSERT ON t032_tmp "
                            "FOR EACH ROW SET @t032 = 1")
                raise AssertionError(
                    "CREATE TRIGGER on a TEMPORARY TABLE unexpectedly succeeded")
            except pymysql.err.OperationalError as e:
                assert e.args[0] == 1361, \
                    "expected 1361 (ER_TRG_ON_VIEW_OR_TEMP_TABLE), got %r" % (e.args,)
                assert "t032_tmp" in e.args[1], e.args

    # Regression: a trigger on an ordinary permanent table must still work.
    _ddl(cluster,
         "DROP TRIGGER IF EXISTS t032_ok",
         "CREATE TRIGGER t032_ok BEFORE INSERT ON t032_base "
         "FOR EACH ROW SET NEW.id = NEW.id + 1")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO t032_base VALUES (1)")
            cur.execute("SELECT * FROM t032_base")
            assert cur.fetchall() == ((2,),)

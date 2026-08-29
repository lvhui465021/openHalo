"""Routine characteristics: DETERMINISTIC volatility, single-statement
RETURN lowering, COMMENT / DEFINER acceptance.

fix.md P1: DETERMINISTIC used to map to IMMUTABLE, letting the planner
constant-fold prepared statements to stale results; it must map to
STABLE (provolatile 's').  fix.md P2: MySQL's one-statement body
"CREATE FUNCTION f() RETURNS int RETURN expr" used to lower to a
LANGUAGE SQL function; it must lower into plmysql so both body forms
share one language, error surface and protocol scope.
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
    # ------------------------------------------------ DETERMINISTIC mapping
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_det",
         """CREATE FUNCTION t006_det() RETURNS INT
         DETERMINISTIC BEGIN RETURN 1; END""")
    out = cluster.psql(
        "SELECT provolatile FROM pg_proc WHERE proname = 't006_det';")
    assert out.strip() == "s", \
        "DETERMINISTIC must map to STABLE, got %r" % out

    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_ndet",
         """CREATE FUNCTION t006_ndet() RETURNS INT
         NOT DETERMINISTIC BEGIN RETURN 1; END""")
    out = cluster.psql(
        "SELECT provolatile FROM pg_proc WHERE proname = 't006_ndet';")
    assert out.strip() == "v", \
        "NOT DETERMINISTIC must stay VOLATILE, got %r" % out

    # A DETERMINISTIC function that reads a table must observe new data on
    # the next execution (STABLE, not constant-folded IMMUTABLE).
    _ddl(cluster,
         "DROP TABLE IF EXISTS t006_t",
         "CREATE TABLE t006_t(x INT)",
         "INSERT INTO t006_t VALUES (1)",
         """CREATE FUNCTION t006_read() RETURNS INT
         DETERMINISTIC BEGIN DECLARE v INT; SELECT x INTO v FROM t006_t;
         RETURN v; END""")
    assert _scalar(cluster, "SELECT t006_read()") == (1,)
    _ddl(cluster, "UPDATE t006_t SET x = 2")
    assert _scalar(cluster, "SELECT t006_read()") == (2,), \
        "DETERMINISTIC function returned a stale (constant-folded) result"

    # --------------------------------- single-statement RETURN -> plmysql
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_ret",
         "CREATE FUNCTION t006_ret() RETURNS INT RETURN 41 + 1")
    out = cluster.psql(
        "SELECT l.lanname, p.prosrc FROM pg_proc p "
        "JOIN pg_language l ON l.oid = p.prolang "
        "WHERE p.proname = 't006_ret';")
    assert out.strip() == "plmysql|BEGIN RETURN 41 + 1; END", \
        "single-statement RETURN body must lower to plmysql, got %r" % out
    assert _scalar(cluster, "SELECT t006_ret()") == (42,)

    # ... with a DETERMINISTIC characteristic in the same statement
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_retdet",
         "CREATE FUNCTION t006_retdet() RETURNS INT DETERMINISTIC RETURN 5")
    out = cluster.psql(
        "SELECT l.lanname, p.provolatile FROM pg_proc p "
        "JOIN pg_language l ON l.oid = p.prolang "
        "WHERE p.proname = 't006_retdet';")
    assert out.strip() == "plmysql|s", "got %r" % out

    # ... with arguments
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_arg",
         "CREATE FUNCTION t006_arg(n INT) RETURNS INT RETURN n * 2")
    assert _scalar(cluster, "SELECT t006_arg(21)") == (42,)

    # ... without a trailing semicolon (EOF lookahead path)
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_eof",
         "CREATE FUNCTION t006_eof() RETURNS INT RETURN 77")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t006_eof';")
    assert out.strip() == "BEGIN RETURN 77; END", "got %r" % out

    # ... with LANGUAGE SQL (a MySQL no-op characteristic) still lowering
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_langsql",
         "CREATE FUNCTION t006_langsql() RETURNS INT LANGUAGE SQL RETURN 7")
    out = cluster.psql(
        "SELECT l.lanname FROM pg_proc p JOIN pg_language l "
        "ON l.oid = p.prolang WHERE p.proname = 't006_langsql';")
    assert out.strip() == "plmysql", "got %r" % out

    # ... and with a compound body (BEGIN...END) alongside: both forms of the
    # same routine must land in the same language
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_cmp",
         """CREATE FUNCTION t006_cmp() RETURNS INT
         BEGIN RETURN 9; END""")
    out = cluster.psql(
        "SELECT l.lanname FROM pg_proc p JOIN pg_language l "
        "ON l.oid = p.prolang WHERE p.proname = 't006_cmp';")
    assert out.strip() == "plmysql", "got %r" % out

    # Protocol scope consistency: both forms refuse PostgreSQL-protocol
    # execution (subprocess.CalledProcessError via ON_ERROR_STOP).
    import subprocess
    cluster.psql("CREATE FUNCTION t006_pg() RETURNS int "
                 "LANGUAGE plmysql AS $$ BEGIN RETURN 1; END $$;")
    try:
        cluster.psql("SELECT t006_pg();")
        raise AssertionError("plmysql routine ran over PG protocol")
    except subprocess.CalledProcessError as e:
        assert "MySQL protocol" in e.stderr, e.stderr

    # ------------------------------------------------ DEFINER / COMMENT
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t006_def",
         """CREATE DEFINER=`halo`@`%` PROCEDURE t006_def()
         COMMENT 'demo procedure'
         BEGIN DECLARE d INT DEFAULT 1; SET d = d + 1; END""")
    out = cluster.psql(
        "SELECT obj_description(p.oid, 'pg_proc') FROM pg_proc p "
        "WHERE p.proname = 't006_def';")
    assert out.strip() == "demo procedure", "COMMENT lost: %r" % out
    assert _scalar(cluster,
                   "SELECT ROUTINE_COMMENT FROM information_schema.ROUTINES "
                   "WHERE ROUTINE_SCHEMA = 'public' AND ROUTINE_NAME = 't006_def'") == ("demo procedure",)
    assert _scalar(cluster,
                   "SELECT comment FROM mysql.proc "
                   "WHERE db = 'public' AND name = 't006_def'") == ("demo procedure",)

    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t006_deffn",
         "CREATE DEFINER=`halo`@`localhost` FUNCTION t006_deffn() "
         "RETURNS INT COMMENT 'fn' RETURN 3")
    assert _scalar(cluster, "SELECT t006_deffn()") == (3,)

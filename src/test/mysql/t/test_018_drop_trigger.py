"""MySQL DROP TRIGGER resolves the owning table from a schema-scoped name.

MySQL spells DROP TRIGGER without an ON-table clause ("DROP TRIGGER
[schema.]name") because trigger names are schema-scoped there, while
PostgreSQL keeps them table-scoped.  The utility layer rewrites the MySQL
form to the PostgreSQL [table, trigger] shape before dropping.  These tests
cover both spellings, IF EXISTS, the MySQL 1360 error for missing triggers,
dropping after the table is gone, recreation after an explicit drop, and
that a MySQL-named trigger wins over a native PostgreSQL trigger sharing
the same name in the same schema.
"""
import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _trigger_count(cluster, name):
    out = cluster.psql("""
        SELECT count(*) FROM pg_trigger
        WHERE tgname = '%s' AND NOT tgisinternal;""" % name)
    return int(out.strip())


def _create_trigger(cluster):
    _ddl(cluster, """CREATE TRIGGER t018_trg BEFORE INSERT ON t018_t
                     FOR EACH ROW INSERT INTO t018_log VALUES ('fired')""")


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t018_t",
         "CREATE TABLE t018_t(id INT PRIMARY KEY, val INT)",
         "CREATE TABLE t018_log(tag VARCHAR(16))")

    # 1) Unqualified MySQL drop removes the trigger; a later INSERT proves
    #    it no longer fires.
    _create_trigger(cluster)
    assert _trigger_count(cluster, "t018_trg") == 1, "trigger was not created"
    _ddl(cluster, "DROP TRIGGER t018_trg")
    assert _trigger_count(cluster, "t018_trg") == 0, \
        "unqualified MySQL DROP TRIGGER did not remove the trigger"
    _ddl(cluster, "INSERT INTO t018_t VALUES (1, 1)")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM t018_log")
            assert cur.fetchone() == (0,), \
                "trigger still fired after unqualified MySQL DROP TRIGGER"

    # 2) The private trigger function survives the drop, so the same name
    #    can be recreated without OR REPLACE.
    _create_trigger(cluster)
    _ddl(cluster, "INSERT INTO t018_t VALUES (2, 2)")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM t018_log")
            assert cur.fetchone() == (1,), \
                "same-name trigger did not fire after recreation"

    # 3) Schema-qualified MySQL drop.
    _ddl(cluster, "DROP TRIGGER public.t018_trg")
    assert _trigger_count(cluster, "t018_trg") == 0, \
        "schema-qualified MySQL DROP TRIGGER did not remove the trigger"

    # 4) PostgreSQL spelling keeps working on the same MySQL-protocol
    #    connection (it shares the "DROP TRIGGER name" prefix).
    _create_trigger(cluster)
    _ddl(cluster, "DROP TRIGGER t018_trg ON t018_t")
    assert _trigger_count(cluster, "t018_trg") == 0, \
        "PostgreSQL DROP TRIGGER ... ON regressed"

    # 5) COMMENT ON TRIGGER shares the reworked grammar path.
    _create_trigger(cluster)
    _ddl(cluster, "COMMENT ON TRIGGER t018_trg ON t018_t IS 't018 comment'")
    out = cluster.psql("""
        SELECT description FROM pg_description d
        JOIN pg_trigger t ON d.objoid = t.oid
        WHERE t.tgname = 't018_trg';""")
    assert out.strip() == "t018 comment", \
        "COMMENT ON TRIGGER regressed: %r" % (out,)
    _ddl(cluster, "DROP TRIGGER t018_trg")

    # 6) Missing trigger without IF EXISTS is MySQL error 1360, not the
    #    generic 1105 fallback.
    try:
        _ddl(cluster, "DROP TRIGGER t018_trg")
        raise AssertionError("DROP TRIGGER of a missing trigger succeeded")
    except (pymysql.err.ProgrammingError, pymysql.err.OperationalError,
            pymysql.err.InternalError) as e:
        assert e.args[0] == 1360, \
            "missing trigger must map to 1360, got %r" % (e.args,)

    # 7) IF EXISTS succeeds on a missing trigger.
    _ddl(cluster, "DROP TRIGGER IF EXISTS t018_trg")
    _ddl(cluster, "DROP TRIGGER IF EXISTS public.t018_trg")

    # 8) Dropping the table removes the trigger row even though the private
    #    function lingers, so a later MySQL DROP TRIGGER must report 1360.
    _create_trigger(cluster)
    _ddl(cluster,
         "DROP TABLE t018_t",
         "CREATE TABLE t018_t(id INT PRIMARY KEY, val INT)")
    try:
        _ddl(cluster, "DROP TRIGGER t018_trg")
        raise AssertionError("DROP TRIGGER after DROP TABLE succeeded")
    except (pymysql.err.ProgrammingError, pymysql.err.OperationalError,
            pymysql.err.InternalError) as e:
        assert e.args[0] == 1360, \
            "orphaned trigger name must map to 1360, got %r" % (e.args,)

    # 9) A MySQL-created trigger wins over a native PostgreSQL trigger with
    #    the same name in the same schema; the native one must survive.
    _create_trigger(cluster)
    cluster.psql("""
        CREATE TABLE t018_other(id INT);
        CREATE FUNCTION t018_dummy() RETURNS trigger
        LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
        CREATE TRIGGER t018_trg BEFORE INSERT ON t018_other
        FOR EACH ROW EXECUTE FUNCTION t018_dummy();""")
    _ddl(cluster, "DROP TRIGGER t018_trg")
    out = cluster.psql("""
        SELECT count(*) FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        WHERE t.tgname = 't018_trg' AND c.relname = 't018_other';""")
    assert out.strip() == "1", \
        "MySQL DROP TRIGGER removed the native PostgreSQL trigger twin"
    _ddl(cluster, "DROP TRIGGER t018_trg ON t018_other")
    assert _trigger_count(cluster, "t018_trg") == 0, \
        "native PostgreSQL twin trigger could not be dropped afterwards"

    _ddl(cluster, "DROP TABLE IF EXISTS t018_t")
    cluster.psql("DROP TABLE t018_other")

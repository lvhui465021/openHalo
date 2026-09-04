"""MySQL CREATE TRIGGER lowers to a private plmysql trigger function.

The test covers both legal MySQL body shapes: a BEGIN...END compound body and
a single statement (sent without a trailing semicolon, as most protocol
clients do).  It also checks that MySQL metadata exposes the original body,
not the PostgreSQL RETURN wrapper required by a trigger function.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t017_audit",
         "DROP TABLE IF EXISTS t017_src",
         "CREATE TABLE t017_src(id INT PRIMARY KEY, val INT)",
         "CREATE TABLE t017_audit(kind VARCHAR(16), oldval INT, newval INT)")

    # Compound body: NEW is mutable in a BEFORE row trigger, and the nested
    # INSERT proves the plmysql trigger function executes under the MySQL
    # protocol path rather than merely being created.
    _ddl(cluster, """
        CREATE DEFINER=`halo`@`localhost` TRIGGER t017_before
        BEFORE INSERT ON t017_src FOR EACH ROW
        BEGIN
          SET NEW.val = NEW.val + 1;
          INSERT INTO t017_audit VALUES ('before', NULL, NEW.val);
        END""")

    # Single-statement body deliberately has no semicolon.  PyMySQL sends
    # command text as-is, so this exercises end-of-input body capture.
    _ddl(cluster, """
        CREATE TRIGGER t017_after
        AFTER UPDATE ON t017_src FOR EACH ROW
        INSERT INTO t017_audit VALUES ('after', OLD.val, NEW.val)""")

    _ddl(cluster,
         "INSERT INTO t017_src VALUES (1, 10)",
         "UPDATE t017_src SET val = 20 WHERE id = 1")

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, val FROM t017_src")
            assert cur.fetchone() == (1, 20), "BEFORE trigger did not update NEW"
            cur.execute("SELECT kind, oldval, newval FROM t017_audit ORDER BY kind")
            assert cur.fetchall() == (("after", 11, 20), ("before", None, 11)), \
                "trigger bodies did not observe OLD/NEW correctly"
            cur.execute("SHOW CREATE TRIGGER t017_before")
            show = cur.fetchone()

    assert show[0] == "t017_before", "SHOW CREATE name: %r" % (show,)
    assert "CREATE DEFINER=`halo`@`localhost` TRIGGER `t017_before` BEFORE INSERT" in show[2], \
        "SHOW CREATE prefix: %r" % (show[2],)
    assert "BEGIN" in show[2] and "SET NEW.val = NEW.val + 1" in show[2], \
        "SHOW CREATE must contain original compound body: %r" % (show[2],)
    assert "RETURN NEW" not in show[2], \
        "SHOW CREATE leaked PostgreSQL wrapper: %r" % (show[2],)

    out = cluster.psql("""
        SELECT prosrc, array_to_string(proconfig, ',')
        FROM pg_proc
        WHERE proname LIKE '%t017_before' AND proname LIKE '__mysql_trigger%';""")
    assert "RETURN NEW;" in out, "generated trigger function lacks RETURN NEW: %r" % out
    assert "plmysql.trigger_body=BEGIN" in out, \
        "original body was not recorded in proconfig: %r" % out
    assert "plmysql.definer=halo@localhost" in out, \
        "trigger DEFINER was not recorded in proconfig: %r" % out

    out = cluster.psql("""
        SELECT action_statement
        FROM mys_informa_schema.triggers
        WHERE trigger_schema = 'public' AND trigger_name = 't017_after';""")
    assert out.strip().startswith("INSERT INTO t017_audit"), \
        "single trigger body was not preserved: %r" % out

    # Dropping the table drops native pg_trigger rows but (by PostgreSQL
    # design) not their functions.  The private function is CREATE OR
    # REPLACE, so a MySQL trigger with the same name can be created again.
    _ddl(cluster,
         "DROP TABLE t017_src",
         "CREATE TABLE t017_src(id INT PRIMARY KEY, val INT)",
         """CREATE TRIGGER t017_before BEFORE INSERT ON t017_src FOR EACH ROW
            SET NEW.val = NEW.val + 1""",
         # A trailing terminator must remain the outer CREATE TRIGGER
         # terminator, rather than becoming part of its simple body.
         """CREATE TRIGGER t017_after_semicolon AFTER INSERT ON t017_src FOR EACH ROW
            INSERT INTO t017_audit VALUES ('semicolon', NULL, NEW.val);""",
         "INSERT INTO t017_src VALUES (2, 1)")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT val FROM t017_src WHERE id = 2")
            assert cur.fetchone() == (2,), \
                "same-name trigger recreation did not replace private function"
            cur.execute("SELECT newval FROM t017_audit WHERE kind = 'semicolon'")
            assert cur.fetchone() == (2,), \
                "simple trigger body with a trailing semicolon was not executed"

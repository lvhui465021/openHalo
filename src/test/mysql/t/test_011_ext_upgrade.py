"""aux_mysql upgrade path: an existing aux_mysql 1.5 database gains the
plmysql language either through the documented upgrade procedure
(CREATE EXTENSION plmysql; ALTER EXTENSION aux_mysql UPDATE) or fails
loudly when the prerequisite is missing.

This file is deliberately named so it runs RIGHT AFTER test_000_smoke,
before any plmysql routines exist in the cluster -- the simulation drops
the plmysql language, which would fail if user routines depended on it.
"""


def _sql(cluster, stmt):
    import subprocess
    try:
        return cluster.psql(stmt)
    except subprocess.CalledProcessError as e:
        raise AssertionError("psql failed: %s" % (e.stderr or e))


def run(cluster):
    # First drop every plmysql routine created by earlier tests: the
    # simulation below drops the language itself, which is only possible
    # when nothing depends on it.
    rows = _sql(cluster, """
        SELECT concat('DROP ',
               CASE prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
               ' ', proname, '(',
               coalesce(pg_get_function_identity_arguments(oid), ''), ');')
        FROM pg_proc
        WHERE prolang = (SELECT oid FROM pg_language
                         WHERE lanname = 'plmysql')
          AND proname NOT LIKE 'plmysql_%';""")
    for line in rows.strip().splitlines():
        if line.strip():
            _sql(cluster, line.strip())

    # ------------------------------------------ simulate an old 1.5 database
    # Fresh installs are already at 1.6 with plmysql present; rewind the
    # extension catalog to the pre-M1 state: aux_mysql 1.5, no plmysql
    # dependency, no plmysql language.
    _sql(cluster, """
        BEGIN;
        DELETE FROM pg_depend
        WHERE deptype = 'n'
          AND objid = (SELECT oid FROM pg_extension WHERE extname = 'aux_mysql')
          AND refobjid = (SELECT oid FROM pg_extension WHERE extname = 'plmysql');
        DROP EXTENSION plmysql;
        UPDATE pg_extension SET extversion = '1.5' WHERE extname = 'aux_mysql';
        COMMIT;""")
    out = _sql(cluster, "SELECT count(*) FROM pg_language WHERE lanname = 'plmysql';")
    assert out.strip() == "0", out
    out = _sql(cluster, "SELECT extversion FROM pg_extension WHERE extname = 'aux_mysql';")
    assert out.strip() == "1.5", out

    # ------------------------------ the upgrade must fail loudly w/o plmysql
    # finally_guard() is a safety net for when this negative check itself
    # misbehaves, not a step in the normal flow: on the expected outcome
    # (upgrade fails, plmysql still missing) the next section's own
    # "CREATE EXTENSION plmysql;" is what's supposed to restore it.
    try:
        upgrade_failed = False
        try:
            _sql(cluster, "ALTER EXTENSION aux_mysql UPDATE;")
        except AssertionError as e:
            upgrade_failed = True
            assert "plmysql" in str(e), e
        assert upgrade_failed, "aux_mysql 1.5->1.6 succeeded without plmysql"
    except Exception:
        finally_guard(cluster)
        raise

    # -------------------------------------- the documented upgrade procedure
    _sql(cluster, "CREATE EXTENSION plmysql;")
    _sql(cluster, "ALTER EXTENSION aux_mysql UPDATE;")
    out = _sql(cluster, "SELECT extversion FROM pg_extension WHERE extname = 'aux_mysql';")
    assert out.strip() == "1.12", out
    out = _sql(cluster, "SELECT count(*) FROM pg_language WHERE lanname = 'plmysql';")
    assert out.strip() == "1", out

    # the upgraded database can create and run MySQL routines
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CREATE PROCEDURE t011_p() BEGIN SET @t011 = 1; END")
            cur.execute("CALL t011_p()")
    out = _sql(cluster, "SELECT count(*) FROM pg_proc WHERE proname = 't011_p';")
    assert out.strip() == "1", out


def finally_guard(cluster):
    """Restore a usable state even if the negative test misbehaved."""
    try:
        out = _sql(cluster, "SELECT count(*) FROM pg_language WHERE lanname = 'plmysql';")
        if out.strip() == "0":
            _sql(cluster, "CREATE EXTENSION plmysql;")
    except Exception:
        pass

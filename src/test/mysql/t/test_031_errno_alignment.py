"""D-category error-code alignment: two of the gap-analysis report's
strictness/error-code items (M12), fixed independently of C2's remaining
SQL SECURITY DEFINER question.

MySQL reports a specific errno for these two cases; openHalo used to fall
through to the generic 1064 syntax-error / 1105 unmapped-error codes because
nothing set mysSetPendingMySQLErrno() before the ereport()/elog() call, even
though the message text was already correct (or close to it) in both cases.
"""

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    # ER_SP_UNDECLARED_VAR (1327): assigning to a name that isn't a declared
    # local variable, a MySQL system variable, or a "@uservar" -- so it's
    # genuinely just an undeclared identifier, not any of the other SET
    # forms this grammar recognizes.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("DROP PROCEDURE IF EXISTS t031_undecl")
                cur.execute("CREATE PROCEDURE t031_undecl() "
                            "BEGIN SET totally_undeclared_name = 1; END")
                raise AssertionError(
                    "CREATE with an undeclared SET target unexpectedly compiled")
            except pymysql.err.OperationalError as e:
                assert e.args[0] == 1327, \
                    "expected 1327 (ER_SP_UNDECLARED_VAR), got %r" % (e.args,)
                assert "totally_undeclared_name" in e.args[1], e.args

    # ER_UNKNOWN_SYSTEM_VARIABLE (1193): reading a "@@name" that isn't a
    # real MySQL system variable.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("SELECT @@totally_not_a_real_sysvar")
                raise AssertionError(
                    "SELECT of an unknown @@sysvar unexpectedly succeeded")
            except pymysql.err.OperationalError as e:
                assert e.args[0] == 1193, \
                    "expected 1193 (ER_UNKNOWN_SYSTEM_VARIABLE), got %r" % (e.args,)
                assert "totally_not_a_real_sysvar" in e.args[1], e.args

    # Regression: a real, known @@sysvar must still read back fine, and a
    # legitimately declared local variable must still work as a SET target.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t031_ok",
         "CREATE PROCEDURE t031_ok() "
         "BEGIN DECLARE v INT DEFAULT 0; SET v = 1; SET @t031 = v; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT @@sql_mode")
            cur.fetchone()
            cur.execute("CALL t031_ok()")
            cur.fetchall()
            cur.execute("SELECT @t031")
            assert cur.fetchone() in ((1,), ('1',))

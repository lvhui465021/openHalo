"""SET <system-var> = expr inside a routine body (no "@" prefix).

MySQL lets a routine body assign a session system variable with a bare
"SET sql_mode = 'TRADITIONAL'" -- no "@" and no "SESSION"/"GLOBAL" keyword.
Textually this is indistinguishable, at the point plmysql's grammar has to
decide, from "SET <undeclared-local-var> = expr": both reach the grammar as
K_SET T_WORD, since a bare word that doesn't name a declared plmysql datum
always lexes as T_WORD regardless of what it names. Before this fix, every
such statement was rejected with "<name> is not a known variable" (1064),
which was correct for a genuinely bad name but wrong for a real system
variable.

The fix consults isSystemVariable() (the same registry the top-level MySQL
SET statement already uses) to tell the two cases apart: a known system
variable name is handed to SPI verbatim, exactly like the pre-existing
"SET @uservar = expr" passthrough; anything else keeps the original
"not a known variable" error.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t027_set_sql_mode",
         "CREATE PROCEDURE t027_set_sql_mode() "
         "BEGIN SET SQL_MODE='TRADITIONAL'; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t027_set_sql_mode()")
            cur.fetchall()
            cur.execute("SELECT @@sql_mode")
            assert cur.fetchone() == ('TRADITIONAL',)
            # leave the session as found for any test that runs after this
            cur.execute("SET SQL_MODE=''")

    # Regression: a genuinely undeclared local variable must still error.
    _ddl(cluster, "DROP PROCEDURE IF EXISTS t027_bad_var")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            raised = False
            try:
                cur.execute("CREATE PROCEDURE t027_bad_var() "
                            "BEGIN SET notavariable = 1; END")
            except Exception as e:
                raised = True
                assert getattr(e, "args", [None])[0] == 1064, e
            assert raised, "SET of an undeclared local variable must still error"

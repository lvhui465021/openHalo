"""SET @@system_var = expr inside a routine body.

The MySQL core lexer hands "@@name" (with any GLOBAL./SESSION./local.
prefix folded into the token) to plmysql as one MysSysVarName token, so
"SET @@sql_mode = 'ANSI'" never reaches the bare-word system-variable
path (test_027: "SET sql_mode = ...") and used to fail as an unknown
plmysql variable.  The grammar now hands the whole statement to SPI
verbatim -- the same passthrough "SET @uservar = expr" already uses --
so it runs through the top-level SET machinery of the CALLer's session.

MySQL resolves system-variable names while compiling the routine, not
only at execution, so every @@name in the captured statement text is
validated against the sysvar registry at CREATE time and an unknown
name fails with ER_UNKNOWN_SYSTEM_VARIABLE (1193) before the routine
exists.  The token value itself is not re-read (it is not trustworthy
across the scanner boundary); the names are scanned out of the captured
statement text, which also sees through quoted literals.
"""


def run(cluster):
    # SET @@sql_mode inside a body: compiles, and the CALL applies it to
    # the caller's session (read back on the same connection).
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t049_set_atat")
            cur.execute("CREATE PROCEDURE t049_set_atat() "
                        "BEGIN SET @@sql_mode='ANSI'; END")
            cur.execute("CALL t049_set_atat()")
            cur.fetchall()
            cur.execute("SELECT @@sql_mode")
            assert cur.fetchone() == ('ANSI',), cur.fetchall()

            # Scope prefix: the whole "@@name[.prefix]" rides in one token;
            # the prefix is part of the captured text, not the token value.
            cur.execute("DROP PROCEDURE IF EXISTS t049_set_atat_sess")
            cur.execute("CREATE PROCEDURE t049_set_atat_sess() "
                        "BEGIN SET @@session.sql_mode='PIPES_AS_CONCAT'; END")
            cur.execute("CALL t049_set_atat_sess()")
            cur.fetchall()
            cur.execute("SELECT @@sql_mode")
            assert cur.fetchone() == ('PIPES_AS_CONCAT',), cur.fetchall()

            # leave the session as found for any test that runs after this
            cur.execute("SET @@sql_mode=''")

    # Unknown system variable: MySQL rejects the routine at CREATE time
    # with 1193, not at CALL time.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            raised = False
            try:
                cur.execute("CREATE PROCEDURE t049_bad_sysvar() "
                            "BEGIN SET @@definitely_not_a_sysvar = 1; END")
            except Exception as e:
                raised = True
                assert getattr(e, "args", [None])[0] == 1193, e
            assert raised, "SET @@<unknown> in a body must fail at CREATE time"

    # @@identity (aux_mysql 1.16 registers the LAST_INSERT_ID synonym as a
    # plain writable session variable) is assignable from a body.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t049_set_identity")
            cur.execute("CREATE PROCEDURE t049_set_identity() "
                        "BEGIN SET @@identity = 7; END")
            cur.execute("CALL t049_set_identity()")
            cur.fetchall()
            cur.execute("SELECT @@identity")
            assert cur.fetchone() == ('7',), cur.fetchall()

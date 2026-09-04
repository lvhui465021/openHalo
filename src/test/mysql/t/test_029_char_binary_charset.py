"""CHAR(n)/VARCHAR(n) BINARY / CHARACTER SET x on a RETURNS type must not
crash the server, and should parse (accepted, silently ignored -- neither
openHalo nor real MySQL columns in this codebase have charset-aware CHAR
storage, so there is nothing meaningful to apply these to yet; see the
compat report's B2 item).

Found while investigating B2: a bare trailing "BINARY" after CHAR(n)/
VARCHAR(n) (i.e. with no CHARACTER SET/CHARSET before it) fell through
every alternative of opt_charset_with_opt_binary in mys_gram.y -- that
production's only non-empty alternative required a CHARACTER SET/CHARSET
clause first; a lone trailing BINARY was left commented out. This didn't
surface as a clean syntax error: it crashed the backend with SIGSEGV
(confirmed via the server log's "terminated by signal 11" for
"CREATE FUNCTION f() RETURNS CHAR(10) BINARY ..."), taking down every
other session on the connection too ("terminating any other active
server processes"). RETURNS was the only place this crashed --
DECLARE/parameter-type BINARY hit a different, more restrictive type
grammar that already gave a clean 1064 instead.

The fix adds the two missing alternatives (bare BINARY, and
BINARY CHARACTER SET/CHARSET x -- MySQL's other permitted ordering,
CHARSET-then-BINARY was already handled) so every ordering parses cleanly
instead of leaving a token the grammar wasn't prepared for.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t029_binary",
         "CREATE FUNCTION t029_binary() RETURNS CHAR(10) BINARY RETURN 'x'",
         "DROP FUNCTION IF EXISTS t029_charset",
         "CREATE FUNCTION t029_charset() RETURNS CHAR(10) CHARACTER SET koi8r "
         "RETURN 'x'",
         "DROP FUNCTION IF EXISTS t029_charset_then_binary",
         "CREATE FUNCTION t029_charset_then_binary() "
         "RETURNS CHAR(10) CHARACTER SET koi8r BINARY RETURN 'x'",
         "DROP FUNCTION IF EXISTS t029_binary_then_charset",
         "CREATE FUNCTION t029_binary_then_charset() "
         "RETURNS CHAR(10) BINARY CHARACTER SET koi8r RETURN 'x'",
         "DROP FUNCTION IF EXISTS t029_varchar_charset",
         "CREATE FUNCTION t029_varchar_charset() RETURNS VARCHAR(10) CHARSET utf8 "
         "RETURN 'x'")

    # Not just "doesn't crash": the function must actually work, since the
    # attribute is meant to be accepted-and-ignored, not silently corrupt
    # the rest of the type.
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t029_binary(), t029_charset(), "
                        "t029_charset_then_binary(), t029_binary_then_charset(), "
                        "t029_varchar_charset()")
            assert cur.fetchone() == ('x', 'x', 'x', 'x', 'x')

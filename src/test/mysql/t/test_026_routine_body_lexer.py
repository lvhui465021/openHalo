"""PL/MySQL routine bodies must be lexed with MySQL rules, not PostgreSQL's.

pl_scanner.c (the lexer plmysql's own pl_gram.y bison parser pulls tokens
from) called PostgreSQL's standard core lexer (core_yylex/scanner_init, from
src/backend/parser/scan.l) unconditionally. That lexer treats a double-quoted
literal as a delimited identifier, exactly like PostgreSQL does outside
ANSI_QUOTES mode -- so any double-quoted string appearing directly in a
routine body (as opposed to inside a string handed off wholesale to the
top-level MySQL parser) came out as an identifier instead of a MySQL string,
and an empty one ("") hit PostgreSQL's own "zero-length delimited identifier"
error. This was invisible for whole-statement bodies scanned by mys_gram.y/
mys_scan.l (which already got the sql_mode-aware ANSI_QUOTES/double-quote
handling in an earlier fix), but plmysql's own body compiler never went
through that MySQL-aware scanner at all -- it always used PostgreSQL's.

The fix points pl_scanner.c at mys_core_yylex/mys_scanner_init (from
mys_scanner.h) instead, which is the same core-scanner infrastructure
mys_gram.y itself uses. This is a lexer swap only: plmysql keeps its own
PL-language keyword lists (BEGIN/DECLARE/LOOP/...) for keyword recognition
-- only the classification of non-keyword lexemes (string/identifier/
operator literals) changes, from PostgreSQL rules to MySQL's.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    # RETURN of an empty double-quoted string must be treated as a MySQL
    # string literal ('' equivalent), not a PostgreSQL delimited identifier.
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t026_dq_empty",
         "CREATE FUNCTION t026_dq_empty() RETURNS CHAR(10) RETURN \"\"")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t026_dq_empty()")
            assert cur.fetchone() == ('',)

    # A non-empty double-quoted string, and CONCAT() of one, inside a
    # BEGIN...END body.
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t026_dq_concat",
         "CREATE FUNCTION t026_dq_concat(a CHAR(10)) RETURNS CHAR(20) "
         "BEGIN RETURN CONCAT(a, \" world\"); END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t026_dq_concat('hello')")
            assert cur.fetchone() == ('hello world',)

    # Backtick-quoted identifiers referenced from inside a routine body must
    # keep working too (same lexer-selection fix, different token class).
    _ddl(cluster,
         "DROP TABLE IF EXISTS `t026_bt`",
         "CREATE TABLE `t026_bt` (`id` INT)",
         "DROP PROCEDURE IF EXISTS t026_bt_proc",
         "CREATE PROCEDURE t026_bt_proc() "
         "BEGIN INSERT INTO `t026_bt` (`id`) VALUES (1); END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t026_bt_proc()")
            cur.fetchall()
            cur.execute("SELECT * FROM `t026_bt`")
            assert cur.fetchall() == ((1,),)

    # Regression: plain single-quoted strings inside a body must still work.
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t026_sq",
         "CREATE FUNCTION t026_sq() RETURNS CHAR(10) RETURN 'ok'")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t026_sq()")
            assert cur.fetchone() == ('ok',)

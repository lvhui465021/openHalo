"""A1 follow-up: a single-statement routine body whose one statement is
itself a compound flow-control construct (WHILE/REPEAT/IF/CASE), a DDL
statement (CREATE/DROP/ALTER), or a transaction-control statement
(START TRANSACTION/COMMIT), with no enclosing BEGIN...END.

MySQL 5.7's own sp.test regression suite has several routines shaped
exactly this way, e.g. "CREATE PROCEDURE a0(x INT) WHILE x DO ... END
WHILE" -- no BEGIN at all. mysql_single_stmt_body_leader (mys_gram.y,
added for A1) already accepted a bare SELECT/INSERT/UPDATE/DELETE/
REPLACE/CALL/SET as a routine's entire body, but WHILE/REPEAT/IF/CASE/
CREATE/DROP were still rejected as a syntax error: replaying that corpus
is what turned this gap up.

Two bugs had to be fixed together to close it:

1. The single-statement leader production's action passed a hardcoded
   SELECT placeholder to the capture helper regardless of which keyword
   actually matched, on the theory that the capture helper only ever
   checked for BEGIN_P. Once the capture helper needed to also recognize
   WHILE/REPEAT/IF/CASE specifically (see next point), that placeholder
   had to become the real matched token instead
   (mysql_single_stmt_body_leader's %type changed from <keyword> to
   <ival> so each alternative can return its own token code).

2. WHILE/REPEAT/IF/LOOP are *compound* statements with their own nested
   semicolons and their own "END <keyword>" terminator -- scanning to the
   first top-level ';' (which is exactly right for a bare
   INSERT/UPDATE/... statement) stops partway through a loop body. These
   need the same nesting-aware capture a BEGIN...END body already gets
   (mys_capture_routine_body()), just seeded to treat one block of that
   kind as already open (since there is no enclosing BEGIN here) --
   mys_capture_routine_body() gained a leading_uncounted_kind parameter
   for exactly this. CASE needed a narrower, separate fix: it already
   used the BEGIN-style depth-tracked capture, but that path deliberately
   drops a trailing "CASE" off "END CASE" for its *normal* case (a nested
   CASE statement inside a BEGIN body, where dropping it is correct
   because nothing else in the substring needs it) -- when CASE is
   *itself* the outermost, leading construct with nothing to wrap it,
   that trailing "CASE" is the only place its own closer's suffix comes
   from, and dropping it breaks plmysql's own re-parse of the wrapped
   text. See MYS_LEADING_CASE in mys_gram.y.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t034_t",
         "CREATE TABLE t034_t (id VARCHAR(16), data INT)")

    # WHILE, no BEGIN.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_while",
         """CREATE PROCEDURE t034_while(x INT)
         WHILE x > 0 DO
           INSERT INTO t034_t VALUES ("w", x);
           SET x = x - 1;
         END WHILE""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_while(2)")
            cur.fetchall()
            cur.execute("SELECT * FROM t034_t WHERE id = 'w' ORDER BY data")
            assert cur.fetchall() == (('w', 1), ('w', 2))

    # REPEAT, no BEGIN.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_repeat",
         """CREATE PROCEDURE t034_repeat(x INT)
         REPEAT
           INSERT INTO t034_t VALUES ("r", x);
           SET x = x - 1;
         UNTIL x = 0 END REPEAT""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_repeat(2)")
            cur.fetchall()
            cur.execute("SELECT * FROM t034_t WHERE id = 'r' ORDER BY data")
            assert cur.fetchall() == (('r', 1), ('r', 2))

    # REPEAT, no BEGIN, whose body calls the REPEAT(str,count) builtin --
    # taken directly from MySQL 5.7's own sp.test (procedure "b"). REPEAT
    # the loop keyword and REPEAT() the function share one token; a bare
    # leading REPEAT loop (no enclosing BEGIN) is only recognized as
    # closed when mys_capture_routine_body()'s seeded nesting tally for
    # that keyword returns to exactly zero, so an uncounted function-call
    # occurrence of the same keyword inside the loop body must not be
    # allowed to inflate that tally, or the real "END REPEAT" can never
    # bring it back to zero and the capture runs off the end of the
    # input. See the REPEAT-specific carve-out in mys_capture_routine_body
    # for why this disambiguation is safe for REPEAT but not for IF/WHILE.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_repeat_fn_collision",
         """CREATE PROCEDURE t034_repeat_fn_collision(x INT)
         REPEAT
           INSERT INTO t034_t VALUES (REPEAT("q", 3), x);
           SET x = x - 1;
         UNTIL x = 0 END REPEAT""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_repeat_fn_collision(2)")
            cur.fetchall()
            cur.execute(
                "SELECT * FROM t034_t WHERE id = 'qqq' ORDER BY data")
            assert cur.fetchall() == (('qqq', 1), ('qqq', 2))

    # IF/ELSEIF/ELSE, no BEGIN.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_if",
         """CREATE PROCEDURE t034_if(x INT)
         IF x < 0 THEN
           INSERT INTO t034_t VALUES ("f", 0);
         ELSEIF x = 0 THEN
           INSERT INTO t034_t VALUES ("f", 1);
         ELSE
           INSERT INTO t034_t VALUES ("f", 2);
         END IF""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_if(0)")
            cur.fetchall()
            cur.execute("SELECT * FROM t034_t WHERE id = 'f'")
            assert cur.fetchall() == (('f', 1),)

    # CASE statement, no BEGIN -- exercises the MYS_LEADING_CASE fix
    # specifically (its "END CASE" suffix must survive the capture).
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_case",
         """CREATE PROCEDURE t034_case(x INT)
         CASE
         WHEN x < 0 THEN
           INSERT INTO t034_t VALUES ("c", 0);
         WHEN x = 0 THEN
           INSERT INTO t034_t VALUES ("c", 1);
         ELSE
           INSERT INTO t034_t VALUES ("c", 2);
         END CASE""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_case(0)")
            cur.fetchall()
            cur.execute("SELECT * FROM t034_t WHERE id = 'c'")
            assert cur.fetchall() == (('c', 1),)

    # DROP as the entire body.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_drop",
         "DROP DATABASE IF EXISTS t034_nonexistent_db",
         "CREATE PROCEDURE t034_drop() DROP DATABASE IF EXISTS t034_nonexistent_db")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_drop()")
            cur.fetchall()

    # CREATE (a DDL statement) as the entire body.
    _ddl(cluster,
         "DROP TABLE IF EXISTS t034_ddl",
         "DROP PROCEDURE IF EXISTS t034_create")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(
                "CREATE PROCEDURE t034_create(v DATETIME) "
                "CREATE TABLE t034_ddl AS SELECT v AS ts")
            cur.execute("CALL t034_create('2020-01-01')")
            cur.fetchall()
            cur.execute("SELECT * FROM t034_ddl")
            row = cur.fetchall()
            assert len(row) == 1, row

    # ALTER as the entire body -- runs to completion, no runtime caveat.
    _ddl(cluster,
         "DROP TABLE IF EXISTS t034_alter",
         "CREATE TABLE t034_alter (id INT)",
         "DROP PROCEDURE IF EXISTS t034_alter_p",
         "CREATE PROCEDURE t034_alter_p() ALTER TABLE t034_alter ADD k INT")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_alter_p()")
            cur.fetchall()
            cur.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name = 't034_alter' ORDER BY column_name")
            assert cur.fetchall() == (('id',), ('k',))

    # COMMIT / START TRANSACTION as the entire body both run at CALL time
    # now: the routine's default DEFINER characteristic is carried as a
    # plmysql.sql_security label item (not pg_proc.prosecdef), so the CALL
    # stays nonatomic (see the C2 fix in the gap-analysis doc and
    # test_030/test_037), and START TRANSACTION lowers to the same
    # implicit-commit-and-reopen action as COMMIT (exec_stmt_start).

    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_commit_p",
         "CREATE PROCEDURE t034_commit_p() COMMIT",
         "DROP PROCEDURE IF EXISTS t034_start_p",
         "CREATE PROCEDURE t034_start_p() START TRANSACTION")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_commit_p()")
            cur.fetchall()
            cur.execute("CALL t034_start_p()")
            cur.fetchall()
    # Regression: WHILE/CASE nested *inside* a BEGIN...END body (the
    # already-working case this fix must not disturb) still work, and a
    # single-statement leader from before this fix (a bare SELECT) is
    # unaffected.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t034_nested",
         """CREATE PROCEDURE t034_nested(x INT)
         BEGIN
           WHILE x > 0 DO
             CASE
             WHEN x = 1 THEN INSERT INTO t034_t VALUES ("n", 1);
             ELSE INSERT INTO t034_t VALUES ("n", 0);
             END CASE;
             SET x = x - 1;
           END WHILE;
         END""",
         "DROP PROCEDURE IF EXISTS t034_sel",
         "CREATE PROCEDURE t034_sel() SELECT * FROM t034_t WHERE id = 'n'")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t034_nested(2)")
            cur.fetchall()
            cur.execute("CALL t034_sel()")
            assert sorted(cur.fetchall()) == [('n', 0), ('n', 1)]

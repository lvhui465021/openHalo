"""SELECT ... INTO OUTFILE / INTO DUMPFILE lowering to COPY (query) TO.

MySQL's SELECT ... INTO OUTFILE 'path' [CHARACTER SET x] [export_options]
must be accepted in both syntax positions and lowered to a server-side
COPY (query) TO 'path' WITH (...):

  * pre-FROM position:  SELECT ... INTO OUTFILE 'f' ... FROM t
  * trailing position:  SELECT ... FROM t ... INTO OUTFILE 'f'
    (after ORDER BY/LIMIT, before FOR UPDATE; also on the outermost node
    of a set operation, where it applies to the whole result)

Option mapping (mys_gram.y -> IntoClause marker -> mys_analyze.c ->
CopyStmt; mys_utility.c applies MySQL's runtime semantics):

  * no options            -> COPY text format (tab-delimited, \n rows,
                             backslash escaping) ~= MySQL defaults
  * FIELDS TERMINATED BY  -> delimiter
  * [OPTIONALLY] ENCLOSED -> FORMAT csv + quote (any option order is
    accepted, matching MySQL's parser)
  * ESCAPED BY '\\'       -> no-op (PG text default already backslash)
  * ESCAPED BY other      -> escape (forces csv; PG text has no escape knob)
  * ESCAPED BY ''         -> rejected 1235 (PG cannot disable escaping)
  * LINES STARTING BY     -> rejected 1235 (PG rows start cleanly)
  * LINES TERMINATED BY   -> '\n' accepted, anything else rejected 1235
  * CHARACTER SET x       -> parsed and ignored

Runtime semantics that COPY does not express live in
mys_prep_outfile_copy_stmt() (mys_utility.c):

  * MySQL refuses to overwrite an existing file: ER_FILE_EXISTS_ERROR
    (1086); PG's COPY TO would silently truncate.
  * INTO DUMPFILE (single-row raw bytes) has no faithful COPY mapping ->
    rejected 1235 rather than silently mis-translated.

Inside plmysql routine bodies, make_execsql_stmt() must NOT parse
INTO OUTFILE / INTO DUMPFILE as an INTO-variables clause (that used to
fail with '"outfile" is not a known variable', 1064 -- MySQL 5.7 corpus
sp.test's b2 and into_outfile procedures).  The clause stays in the
statement text, which the core MySQL parser lowers to the same CopyStmt;
statements after it in the body must still run.
"""

import os
import shutil
import tempfile

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _outfile(cluster, sql, want_errno=None):
    """Run one INTO OUTFILE statement; return (ok, errno)."""
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(sql)
                return True, None
            except pymysql.err.MySQLError as e:
                if want_errno is not None:
                    assert e.args[0] == want_errno, \
                        "expected errno %d, got %r" % (want_errno, e.args,)
                return False, getattr(e, "args", (None,))[0]


class _Outdir:
    """A server-writable scratch directory under /tmp (the server process
    runs as this same test user, so files it writes are ours to read)."""

    def __enter__(self):
        self.path = tempfile.mkdtemp(prefix="halo_outfile_039_")
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.path, ignore_errors=True)

    def file(self, name):
        return os.path.join(self.path, name)


def run(cluster):
    with _Outdir() as out:
        _ddl(cluster,
             "DROP TABLE IF EXISTS t039_t",
             "CREATE TABLE t039_t (id INT, name VARCHAR(20))",
             "INSERT INTO t039_t VALUES (1,'a'),(2,'b,c'),(3,'d')")

        # ---- default form (pre-FROM position): MySQL default separators
        #      are tab-delimited fields, newline rows ----
        f = out.file("default.tsv")
        ok, _ = _outfile(cluster,
                         "SELECT id, name INTO OUTFILE '%s' FROM t039_t" % f)
        assert ok
        assert open(f).read() == "1\ta\n2\tb,c\n3\td\n", \
            "default OUTFILE must be tab-delimited with newline rows"

        # ---- trailing position (INTO after FROM) ----
        f = out.file("trailing.tsv")
        ok, _ = _outfile(cluster,
                         "SELECT id, name FROM t039_t INTO OUTFILE '%s'" % f)
        assert ok
        assert open(f).read() == "1\ta\n2\tb,c\n3\td\n"

        # ---- trailing position after ORDER BY / LIMIT ----
        f = out.file("limit.tsv")
        ok, _ = _outfile(
            cluster,
            "SELECT id, name FROM t039_t ORDER BY id LIMIT 2 "
            "INTO OUTFILE '%s'" % f)
        assert ok
        assert open(f).read() == "1\ta\n2\tb,c\n"

        # ---- FIELDS TERMINATED BY ',' + LINES TERMINATED BY '\n' ----
        # (PG text format keeps MySQL's backslash escaping, so the
        # embedded comma in 'b,c' is escaped.)
        f = out.file("comma.csv")
        ok, _ = _outfile(
            cluster,
            "SELECT id, name INTO OUTFILE '%s' "
            "FIELDS TERMINATED BY ',' LINES TERMINATED BY '\\n' "
            "FROM t039_t" % f)
        assert ok
        assert open(f).read() == "1,a\n2,b\\,c\n3,d\n"

        # ---- ENCLOSED BY '"' -> CSV quoting of the comma-bearing value ----
        f = out.file("enclosed.csv")
        ok, _ = _outfile(
            cluster,
            "SELECT id, name INTO OUTFILE '%s' FIELDS ENCLOSED BY '\"' "
            "FROM t039_t" % f)
        assert ok
        assert open(f).read() == '1,a\n2,"b,c"\n3,d\n'

        # ---- OPTIONALLY ENCLOSED, in an order MySQL's parser accepts ----
        f = out.file("optionally.csv")
        ok, _ = _outfile(
            cluster,
            "SELECT id, name INTO OUTFILE '%s' "
            "FIELDS OPTIONALLY ENCLOSED BY '\"' TERMINATED BY ',' "
            "FROM t039_t" % f)
        assert ok
        assert open(f).read() == '1,a\n2,"b,c"\n3,d\n'

        # ---- ESCAPED BY '\\' is MySQL's default: a no-op here ----
        f = out.file("escaped.tsv")
        ok, _ = _outfile(
            cluster,
            "SELECT id, name INTO OUTFILE '%s' FIELDS ESCAPED BY '\\\\' "
            "FROM t039_t" % f)
        assert ok
        assert open(f).read() == "1\ta\n2\tb,c\n3\td\n"

        # ---- CHARACTER SET is parsed and ignored ----
        f = out.file("charset.tsv")
        ok, _ = _outfile(
            cluster,
            "SELECT id, name INTO OUTFILE '%s' CHARACTER SET utf8mb4 "
            "FROM t039_t" % f)
        assert ok
        assert open(f).read() == "1\ta\n2\tb,c\n3\td\n"

        # ---- union result set (trailing INTO applies to the whole union,
        #      matching MySQL) ----
        f = out.file("union.tsv")
        ok, _ = _outfile(
            cluster,
            "SELECT id FROM t039_t UNION SELECT id + 10 FROM t039_t "
            "INTO OUTFILE '%s'" % f)
        assert ok
        assert sorted(open(f).read().splitlines()) == \
            ["1", "11", "12", "13", "2", "3"], \
            "trailing INTO after a UNION must export the union result"

        # ---- MySQL refuses to overwrite an existing file (1086); PG's
        #      COPY TO would silently truncate, so this is enforced in
        #      mys_utility.c ----
        ok, errno = _outfile(
            cluster,
            "SELECT id INTO OUTFILE '%s' FROM t039_t" % f,
            want_errno=1086)
        assert not ok, "OUTFILE onto an existing file must fail"

        # ---- rejected option combinations (ER_NOT_SUPPORTED_YET, 1235) ----
        _outfile(cluster,
                 "SELECT id INTO OUTFILE '%s' FIELDS ESCAPED BY '' "
                 "FROM t039_t" % out.file("e1"),
                 want_errno=1235)
        _outfile(cluster,
                 "SELECT id INTO OUTFILE '%s' LINES STARTING BY '>>' "
                 "FROM t039_t" % out.file("e2"),
                 want_errno=1235)
        _outfile(cluster,
                 "SELECT id INTO OUTFILE '%s' LINES TERMINATED BY '\\r\\n' "
                 "FROM t039_t" % out.file("e3"),
                 want_errno=1235)
        _outfile(cluster,
                 "SELECT id INTO DUMPFILE '%s' FROM t039_t" % out.file("e4"),
                 want_errno=1235)

        # ---- inside a procedure body (sp.test's into_outfile shape):
        #      the clause must not be parsed as INTO-variables, the file
        #      must be written server-side at CALL time, and statements
        #      AFTER the OUTFILE in the body must still run ----
        f = out.file("proc.tsv")
        _ddl(cluster,
             "DROP PROCEDURE IF EXISTS t039_outfile",
             "CREATE PROCEDURE t039_outfile() "
             "BEGIN "
             "  SELECT * INTO OUTFILE '%s' FROM t039_t; "
             "  INSERT INTO t039_t VALUES (99,'z'); "
             "END" % f)
        _outfile(cluster, "CALL t039_outfile()")
        assert open(f).read() == "1\ta\n2\tb,c\n3\td\n"
        assert _rows(cluster, "SELECT COUNT(*) FROM t039_t") == ((4,),), \
            "statements after INTO OUTFILE in the body must still run"

        # ---- b2 corpus shape: single-statement REPEAT loop body ----
        f = out.file("b2.tsv")
        _ddl(cluster,
             "DROP PROCEDURE IF EXISTS t039_b2",
             "CREATE PROCEDURE t039_b2() "
             "repeat(select 1 into outfile '%s'); until 1 end repeat" % f)
        _outfile(cluster, "CALL t039_b2()")
        assert open(f).read() == "1\n"

        # ---- the CALL itself also refuses to overwrite (1086 at runtime,
        #      matching MySQL's CALL-time behavior) ----
        _outfile(cluster, "CALL t039_outfile()", want_errno=1086)

        # cleanup
        _ddl(cluster,
             "DROP PROCEDURE IF EXISTS t039_outfile",
             "DROP PROCEDURE IF EXISTS t039_b2",
             "DROP TABLE IF EXISTS t039_t")


def _rows(cluster, sql):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchall()

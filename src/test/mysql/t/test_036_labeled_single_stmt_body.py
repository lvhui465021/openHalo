"""A labeled flow-control statement as a routine's entire body.

MySQL's own sp.test regression suite labels whole-body loops and blocks
without any enclosing BEGIN...END: "CREATE PROCEDURE c(x INT) hmm: WHILE
x > 0 DO ... END WHILE hmm".  Two things had to line up for these to
compile: the routine-body capture must start at the label (not at the
leader keyword), and the closer's optional label echo ("END WHILE lbl")
must stay inside the captured text instead of leaking out as the
parser's lookahead.  plmysql's own grammar already understood labels
inside a body; this is purely the capture/grammar layer.
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _rows(cluster, sql):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchall()


def run(cluster):
    _ddl(cluster,
         "DROP TABLE IF EXISTS t036_t",
         "CREATE TABLE t036_t(tag VARCHAR(8), n INT)")

    # Corpus shape 1: labeled WHILE with a closer echo (sp.test procedure c,
    # which also exercises ITERATE inside the loop).
    _ddl(cluster,
         """CREATE PROCEDURE t036_c(x INT)
            hmm: WHILE x > 0 DO
              INSERT INTO t036_t VALUES ('c', x);
              SET x = x - 1;
            END WHILE hmm""",
         "CALL t036_c(3)")
    assert _rows(cluster, "SELECT count(*) FROM t036_t WHERE tag = 'c'") == ((3,),), \
        "labeled WHILE with echo did not run its body three times"

    # Corpus shape 2: labeled WHILE without a closer echo (sp.test procedure
    # d), and a labeled LOOP with echo plus LEAVE out of the middle
    # (sp.test procedure e).
    _ddl(cluster,
         "DELETE FROM t036_t",
         """CREATE PROCEDURE t036_d(x INT)
            hmm: WHILE x > 0 DO
              INSERT INTO t036_t VALUES ('d', x);
              SET x = x - 1;
            END WHILE""",
         """CREATE PROCEDURE t036_e(x INT)
            foo: LOOP
              IF x = 0 THEN
                LEAVE foo;
              END IF;
              INSERT INTO t036_t VALUES ('e', x);
              SET x = x - 1;
            END LOOP foo""",
         "CALL t036_d(2)",
         "CALL t036_e(2)")
    assert _rows(cluster, "SELECT count(*) FROM t036_t WHERE tag = 'd'") == ((2,),), \
        "labeled WHILE without echo did not run"
    assert _rows(cluster, "SELECT count(*) FROM t036_t WHERE tag = 'e'") == ((2,),), \
        "labeled LOOP with echo did not leave at the right iteration"

    # Corpus shape 3: a labeled BEGIN block (sp.test procedure i, whose label
    # sits on its own line in the original).
    _ddl(cluster,
         "DELETE FROM t036_t",
         """CREATE PROCEDURE t036_i(x INT)
            foo:
            BEGIN
              IF x = 0 THEN
                LEAVE foo;
              END IF;
              INSERT INTO t036_t VALUES ('i', x);
            END foo""",
         "CALL t036_i(0)",
         "CALL t036_i(1)")
    assert _rows(cluster, "SELECT count(*) FROM t036_t WHERE tag = 'i'") == ((1,),), \
        "labeled BEGIN block did not leave on the first call or run on the second"

    # The echo must name the opening label, as in MySQL (check_labels in
    # pl_gram.y); a mismatched echo is a compile error, not a silent pass.
    try:
        _ddl(cluster, """CREATE PROCEDURE t036_bad(x INT)
            hmm: WHILE x > 0 DO
              SET x = x - 1;
            END WHILE other""")
        raise AssertionError("mismatched closer echo compiled")
    except Exception as e:
        assert "hmm" in str(e) or "other" in str(e), \
            "mismatched echo must be rejected naming the labels: %r" % (e,)

    # SHOW CREATE keeps the original labeled body verbatim.
    show = _rows(cluster, "SHOW CREATE PROCEDURE t036_c")[0][2]
    assert "hmm: WHILE" in show and "END WHILE hmm" in show, \
        "original labeled body not preserved: %r" % (show,)

    _ddl(cluster,
         "DROP PROCEDURE t036_c",
         "DROP PROCEDURE t036_d",
         "DROP PROCEDURE t036_e",
         "DROP PROCEDURE t036_i",
         "DROP TABLE t036_t")

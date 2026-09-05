"""MySQL FULLTEXT MATCH(cols) AGAINST(...) syntax translation basics.

The mys dialect translates MySQL FULLTEXT to PostgreSQL tsearch:

  * DDL forms (FULLTEXT KEY/INDEX inside CREATE TABLE, CREATE FULLTEXT
    INDEX, ALTER TABLE ... ADD FULLTEXT) are accepted by the grammar
    (the index itself is a plain btree in openHalo; MATCH still works,
    just without a dedicated index);
  * WHERE/HAVING MATCH(...) AGAINST(...) is a predicate: the analyzer
    rewrites the grammar's score call (mysql.match_against, float8) to
    the boolean variant (mysql.match_against_bool) in boolean position;
  * SELECT-list / ORDER BY MATCH(...) AGAINST(...) returns the float8
    relevance score, 0 for non-matching rows (MySQL behavior);
  * mode 0 = natural language (words OR-ed, like MySQL), mode 1 =
    boolean (subset: +word required, -word excluded, "phrase" exact
    phrase, word* prefix; bare words optional), mode 2 = natural with
    query expansion (currently degrades to natural mode).

The text search configuration behind it is the mysql.ft_config custom
GUC (default 'simple'; set 'ngram' for CJK with contrib/ngram).
"""


def _q(cluster, sql):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            return cur


def _ids(cluster, sql):
    cur = _q(cluster, sql)
    try:
        return [r[0] for r in cur.fetchall()]
    finally:
        cur.close()


def _assert(cond, msg):
    if not cond:
        raise AssertionError(msg)


def run(cluster):
    _ddl = []
    with cluster.mysql(dbname="public") as conn:
        cur = conn.cursor()
        cur.execute("DROP TABLE IF EXISTS t044_ft")
        cur.execute("""CREATE TABLE t044_ft (
            id int primary key,
            title text,
            body text,
            FULLTEXT KEY ft_title (title, body))""")
        cur.execute("CREATE FULLTEXT INDEX ft_body ON t044_ft (body)")
        cur.execute("INSERT INTO t044_ft VALUES "
                    "(1, 'quick brown fox', 'the quick brown fox jumps over the lazy dog'),"
                    "(2, 'slow red cat', 'a red cat sleeps all day'),"
                    "(3, 'green garden', 'nothing related to search here'),"
                    "(4, 'quick rabbit', 'quick rabbit runs fast'),"
                    "(5, 'lazy dog', 'a very lazy dog')")
        cur.close()
    # hmm: helpers above open/close their own connections; keep one below

    # -- natural language mode: any query word matches (OR), score ranks --
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('quick brown') ORDER BY id")
    _assert(got == [1, 4], "natural 'quick brown' should match rows 1,4, got %r" % got)
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('rabbit')")
    _assert(got == [4], "natural 'rabbit' should match row 4, got %r" % got)
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('red cat')")
    _assert(got == [2], "natural 'red cat' should match row 2, got %r" % got)

    # -- boolean mode subset ------------------------------------------------
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('+quick -fox' IN BOOLEAN MODE)")
    _assert(got == [4], "'+quick -fox' should match row 4 only, got %r" % got)
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('+lazy +dog' IN BOOLEAN MODE)")
    _assert(set(got) == {1, 5}, "'+lazy +dog' should match rows 1,5, got %r" % got)
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('\"lazy dog\"' IN BOOLEAN MODE)")
    _assert(set(got) == {1, 5}, 'phrase "lazy dog" should match rows 1,5, got %r' % got)
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('ra*' IN BOOLEAN MODE)")
    _assert(got == [4], "prefix 'ra*' should match row 4 (rabbit), got %r" % got)
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('-quick' IN BOOLEAN MODE)")
    _assert(got == [], "negative-only boolean query returns no rows in MySQL 5.7 "
                       "(a positive term is required), got %r" % got)
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('+rabbit -fox' IN BOOLEAN MODE)")
    _assert(got == [4], "'+rabbit -fox' should match row 4, got %r" % got)

    # -- WITH QUERY EXPANSION accepted (natural semantics) ------------------
    got = _ids(cluster, "SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('rabbit' WITH QUERY EXPANSION)")
    _assert(got == [4], "expansion form should match row 4, got %r" % got)

    # -- score expression in SELECT list / ORDER BY -------------------------
    with cluster.mysql(dbname="public") as conn:
        cur = conn.cursor()
        cur.execute("SELECT id, MATCH(body) AGAINST('rabbit') FROM t044_ft ORDER BY id")
        rows = cur.fetchall()
        _assert(len(rows) == 5 and rows[3][0] == 4 and rows[3][1] > 0
                and all(r[1] == 0 for r in rows[:3] + rows[4:]),
                "score expression: only row 4 should score > 0, got %r" % (rows,))
        # ORDER BY relevance: matching rows float to the front (scores can
        # tie here, so only membership is asserted)
        cur.execute("SELECT id FROM t044_ft WHERE MATCH(body) AGAINST('lazy dog') "
                    "ORDER BY MATCH(body) AGAINST('lazy dog') DESC, id")
        top = cur.fetchall()
        _assert(set(r[0] for r in top) == {1, 5} and top[0][0] in (1, 5),
                "ORDER BY relevance should rank the matching rows first, "
                "got %r" % (top,))
        cur.close()

    with cluster.mysql(dbname="public") as conn:
        cur = conn.cursor()
        cur.execute("DROP TABLE IF EXISTS t044_ft")
        cur.close()

"""MySQL allows SHOW statements that produce a result set inside stored
program bodies (sp.test bug2267): SHOW PROCEDURE STATUS, SHOW CREATE
PROCEDURE etc. run during a CALL and stream their result set to the
client like a bare SELECT would.
"""


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        cur = conn.cursor()
        def q(sql):
            cur.execute(sql)
            try:
                return cur.fetchall()
            except Exception:
                return None

        q("DROP PROCEDURE IF EXISTS t047_s1")
        q("DROP PROCEDURE IF EXISTS t047_s2")
        # create both routines in the public schema so SHOW ... WHERE db
        # can find them
        q("CREATE PROCEDURE public.t047_s1() SELECT 1")
        q("""CREATE PROCEDURE public.t047_s2()
BEGIN
  SHOW PROCEDURE STATUS WHERE db='public';
  SHOW CREATE PROCEDURE public.t047_s1;
END""")

        # SHOW PROCEDURE STATUS in a body streams rows on CALL
        cur.execute("call public.t047_s2")
        rows1 = cur.fetchall()
        # first result set: the status row of t047_s2 itself (db, name, type)
        assert rows1 and any(r[0] == 'public' and r[1] == 't047_s2' and
                             r[2] == 'PROCEDURE' for r in rows1), rows1
        assert cur.nextset(), "expected a second result set"
        rows2 = cur.fetchall()
        # second result set: SHOW CREATE PROCEDURE content mentions the body
        assert rows2 and rows2[0][2].startswith('CREATE'), rows2

        q("DROP PROCEDURE public.t047_s1")
        q("DROP PROCEDURE public.t047_s2")
        cur.close()

"""MySQL routine-level characteristics the corpus exercises:

  * CHARSET(str) builtin (sp.test expects 'utf8' for text results);
  * ALTER PROCEDURE / ALTER FUNCTION with MySQL characteristics
    (comment '...', sql security definer, bare ALTER with no
    characteristics), where the comment must land in pg_description.
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

        # -- CHARSET builtin -------------------------------------------------
        q("DROP PROCEDURE IF EXISTS t045_p")
        q("DROP FUNCTION IF EXISTS t045_f1")
        q("DROP FUNCTION IF EXISTS t045_f2")
        q("CREATE FUNCTION t045_f1() RETURNS CHAR(10) RETURN 'abc'")
        q("CREATE FUNCTION t045_f2() RETURNS TEXT RETURN 'abc'")
        r = q("SELECT CHARSET(t045_f1()), CHARSET(t045_f2()), CHARSET('plain')")
        assert r == (('utf8', 'utf8', 'utf8'),), r
        r = q("SELECT CHARSET(NULL)")
        assert r == ((None,),), r

        # -- ALTER ... bare and with MySQL characteristics -------------------
        q("CREATE PROCEDURE t045_p() SELECT 1")
        q("ALTER PROCEDURE t045_p COMMENT '2222222222' SQL SECURITY DEFINER")
        q("ALTER PROCEDURE t045_p COMMENT '3333333333'")
        q("ALTER FUNCTION t045_f1 COMMENT 'Characteristics function test'")
        q("ALTER FUNCTION t045_f1 NO SQL")
        q("ALTER PROCEDURE t045_p READS SQL DATA")
        # comment must have landed in pg_description
        r = q("SELECT obj_description('t045_f1'::regproc, 'pg_proc')")
        assert r == (('Characteristics function test',),), r
        r = q("SELECT obj_description('t045_p'::regproc, 'pg_proc')")
        assert r == (('3333333333',),), r

        q("DROP PROCEDURE t045_p")
        q("DROP FUNCTION t045_f1")
        q("DROP FUNCTION t045_f2")
        cur.close()

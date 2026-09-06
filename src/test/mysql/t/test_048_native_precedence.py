"""MySQL native (built-in) functions win over same-named stored routines
for unqualified calls (creating such a routine emits warning 1585, sp.test
IGNORE_SPACE section): unqualified pi()/database()/md5()/current_user()
stay native; the stored versions need schema qualification.
"""


def run(cluster):
    with cluster.mysql(dbname="public") as conn0:
        with conn0.cursor() as c0:
            c0.execute("CREATE DATABASE IF NOT EXISTS test")
    with cluster.mysql(dbname="test") as conn:
        cur = conn.cursor()
        def q(sql):
            cur.execute(sql)
            try:
                return cur.fetchall()
            except Exception:
                return None

        q("DROP PROCEDURE IF EXISTS t048_pi")
        q("DROP FUNCTION IF EXISTS pi")
        q("DROP FUNCTION IF EXISTS md5")
        q("CREATE FUNCTION pi() RETURNS VARCHAR(50) "
          "RETURN 'pie, my favorite desert.'")
        q("CREATE FUNCTION md5(x VARCHAR(50)) RETURNS VARCHAR(50) "
          "RETURN 'stored-md5'")

        # native functions still win unqualified
        r = q("SELECT pi(), pi ()")
        assert r == ((3.141592653589793, 3.141592653589793),), r
        r = q("SELECT md5('aaa')")
        assert r == (('47bce5c74f589f4867dbd57e9ca9f808',),), r
        r = q("SELECT database()")
        assert r[0][0] == 'test', r

        # schema-qualified calls reach the stored functions
        r = q("SELECT test.pi()")
        assert r == (('pie, my favorite desert.',),), r
        r = q("SELECT test.md5('x')")
        assert r == (('stored-md5',),), r

        # aggregates keep their numeric overloads
        q("CREATE TABLE t048_t(i int)")
        q("INSERT INTO t048_t VALUES (1),(2),(3)")
        r = q("SELECT sum(i), count(i), max(i), avg(i) FROM t048_t")
        assert r == ((6, 3, 3, 2),), r

        q("DROP TABLE t048_t")
        q("DROP FUNCTION pi")
        q("DROP FUNCTION md5")
        cur.close()

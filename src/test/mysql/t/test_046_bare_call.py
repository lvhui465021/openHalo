"""MySQL allows CALL sp_name with no parentheses; that is an invocation
with an empty argument list (sp.test proc_21462, bug47649 etc. rely on
it).  Covered here: plain bare CALL, bare CALL as the last of several
';'-separated statements, and schema-qualified bare CALL.
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

        q("DROP PROCEDURE IF EXISTS t046_p1")
        q("CREATE PROCEDURE t046_p1() SELECT 1")

        # bare CALL (no parens)
        r = q("call t046_p1")
        assert r == ((1,),), r

        # bare CALL with a trailing semicolon
        r = q("call t046_p1;")
        assert r == ((1,),), r

        # bare CALL inside a multi-statement string
        r = q("SELECT 42; call t046_p1")
        assert r == ((42,),), r
        r = q("call t046_p1; call t046_p1()")
        assert r == ((1,),), r

        # schema-qualified bare CALL
        r = q("call public.t046_p1")
        assert r == ((1,),), r

        # parenthesized CALL must keep working
        r = q("CALL t046_p1()")
        assert r == ((1,),), r

        # a procedure with parameters still reports the wrong-arity error
        q("DROP PROCEDURE IF EXISTS t046_p2")
        q("CREATE PROCEDURE t046_p2(x INT) SELECT x")
        try:
            cur.execute("call t046_p2")
            raise AssertionError("expected arity error for call t046_p2")
        except Exception as e:
            assert "t046_p2" in str(e) or "does not exist" in str(e), e

        q("DROP PROCEDURE t046_p1")
        q("DROP PROCEDURE t046_p2")
        cur.close()

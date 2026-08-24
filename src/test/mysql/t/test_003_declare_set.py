"""MySQL SQL/PSM 局部变量声明与赋值。

`_ddl()`/连接都带 dbname="public"：不带的话 MySQL 协议连接的 search_path
只剩 {mysql, pg_catalog}，任何 CREATE 都会先报 1049 "no schema has been
selected to create in"（既有行为，见 test_002 的说明），会在到达 plmysql
语法层之前就失败，掩盖本测试真正要钉的 DECLARE/SET 语法错误。
"""


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t003_p")
            cur.execute("""
                CREATE PROCEDURE t003_p()
                BEGIN
                    DECLARE v INT DEFAULT 1;
                    DECLARE w INT;
                    SET w = v + 41;
                    SELECT w;
                END
            """)
            cur.execute("CALL t003_p()")
            row = cur.fetchone()
            assert row == (42,), "expected (42,), got %r" % (row,)

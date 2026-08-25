"""plmysql 例程只能在 MySQL 协议会话中执行；创建不受限。

`cluster.mysql(dbname="public")`：MySQL 协议连接把请求的 "database" 当 PG
schema 装进 search_path，不传时只剩 {mysql, pg_catalog}，t004_f 建在 public
schema（cluster.psql() 默认 search_path 的第一个真实 schema），不传 dbname
会报 "function t004_f() does not exist"（见 test_002/test_003 的同一说明）。
"""
import subprocess


def run(cluster):
    # 创建：PG 协议下必须成功（pg_restore 场景）
    cluster.psql("""
        CREATE FUNCTION t004_f() RETURNS int
        LANGUAGE plmysql AS $$ BEGIN RETURN 7; END $$;
    """)

    # 执行：PG 协议下必须报错
    try:
        cluster.psql("SELECT t004_f();")
        raise AssertionError("plmysql routine executed over PostgreSQL protocol")
    except subprocess.CalledProcessError as e:
        assert "MySQL protocol" in e.stderr, \
            "wrong error for cross-protocol call: %r" % e.stderr

    # 执行：MySQL 协议下必须成功
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t004_f()")
            row = cur.fetchone()
            assert row == (7,), "expected (7,), got %r" % (row,)

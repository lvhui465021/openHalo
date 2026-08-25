"""plmysql 例程只能在 MySQL 协议会话中执行；创建不受限。

`cluster.mysql(dbname="public")`：MySQL 协议连接把请求的 "database" 当 PG
schema 装进 search_path，不传时只剩 {mysql, pg_catalog}，t004_f 建在 public
schema（cluster.psql() 默认 search_path 的第一个真实 schema），不传 dbname
会报 "function t004_f() does not exist"（见 test_002/test_003 的同一说明）。

**Fix round 1（评审补充）**：`plmysql_inline_handler`（匿名 `DO $$ ... $$
LANGUAGE plmysql;` 代码块）是第二个真实的编译+执行入口，跟 `plmysql_call_handler`
共享同一层协议保护（`plmysql_require_mysql_protocol()`）。下面额外钉住这条路：
PG 协议下执行 DO 块必须报同样的错误，且守卫必须在任何执行逻辑之前生效（用一张
边车表证明 DO 块体里的语句真的一条都没跑）。DO 块走 MySQL 协议这条路本测试不
覆盖——MySQL 协议连接用的是 mys_gram.y 而不是标准 PG 语法，PG 风格的
`DO $$...$$ LANGUAGE x` 语句能否被 MySQL 语法层接受是另一个问题，不是本任务
（协议检查）要钉的行为。
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

    # ---------------------------------------------------- 匿名代码块（DO 语句）
    # plmysql_inline_handler 是第二个真实编译+执行入口，必须有同样的保护。
    cluster.psql("DROP TABLE IF EXISTS t004_do;")
    cluster.psql("CREATE TABLE t004_do (v int);")

    try:
        cluster.psql(
            "DO $$ BEGIN INSERT INTO t004_do VALUES (1); END $$ "
            "LANGUAGE plmysql;")
        raise AssertionError("plmysql DO block executed over PostgreSQL protocol")
    except subprocess.CalledProcessError as e:
        assert "MySQL protocol" in e.stderr, \
            "wrong error for cross-protocol DO block: %r" % e.stderr

    # 守卫必须在任何执行逻辑之前生效：块体里的 INSERT 一条都不该跑
    out = cluster.psql("SELECT count(*) FROM t004_do;")
    assert out.strip() == "0", \
        "DO block partially executed despite protocol rejection: %r" % out

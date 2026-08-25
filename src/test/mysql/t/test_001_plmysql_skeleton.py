"""plmysql 语言已注册且可用（此阶段语法仍等价于 plpgsql）。

**Task 6 后的更新**：t001_add 的创建仍走 PG 协议（`cluster.psql()`），验证
`plmysql_validator` 不做协议限制（pg_restore 链路）；但调用改走 MySQL 协议
（`cluster.mysql(dbname="public")`）——Task 6 给 `plmysql_call_handler` 加了协议
检查，PG 协议下执行 plmysql 例程现在会报错（这正是 test_004_protocol_scope 要
钉的行为），本文件写下时（Task 2）这条限制还不存在，这里同步更新观测方式，语义
（plmysql 能创建、能执行、返回正确结果）不变。`dbname="public"`：MySQL 协议连接
把请求的 "database" 当 PG schema 装进 search_path，不传时只剩
{mysql, pg_catalog}，见 test_002/test_003 的说明。
"""


def run(cluster):
    # 语言存在
    out = cluster.psql("SELECT lanname FROM pg_language WHERE lanname='plmysql';")
    assert out.strip() == "plmysql", "plmysql language not registered: %r" % out

    # 三个 handler 函数存在
    out = cluster.psql(
        "SELECT count(*) FROM pg_proc WHERE proname IN "
        "('plmysql_call_handler','plmysql_inline_handler','plmysql_validator');")
    assert out.strip() == "3", "expected 3 handler functions, got %r" % out

    # 能以 plmysql 创建函数（走 PG 协议，此时用 plpgsql 语法；创建不受协议限制）
    cluster.psql("""
        CREATE FUNCTION t001_add(a int, b int) RETURNS int
        LANGUAGE plmysql AS $$ BEGIN RETURN a + b; END $$;
    """)
    # 执行必须走 MySQL 协议（Task 6：PG 协议下执行 plmysql 例程会报错）
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t001_add(2, 3)")
            row = cur.fetchone()
    assert row == (5,), "expected (5,), got %r" % (row,)

    # 与 plpgsql 是相互独立的两个语言，plpgsql 未被破坏
    cluster.psql("""
        CREATE FUNCTION t001_mul(a int, b int) RETURNS int
        LANGUAGE plpgsql AS $$ BEGIN RETURN a * b; END $$;
    """)
    out = cluster.psql("SELECT t001_mul(2, 3);")
    assert out.strip() == "6", "plpgsql regression: expected 6, got %r" % out

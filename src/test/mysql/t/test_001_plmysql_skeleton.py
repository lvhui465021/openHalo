"""plmysql 语言已注册且可用（此阶段语法仍等价于 plpgsql）。"""


def run(cluster):
    # 语言存在
    out = cluster.psql("SELECT lanname FROM pg_language WHERE lanname='plmysql';")
    assert out.strip() == "plmysql", "plmysql language not registered: %r" % out

    # 三个 handler 函数存在
    out = cluster.psql(
        "SELECT count(*) FROM pg_proc WHERE proname IN "
        "('plmysql_call_handler','plmysql_inline_handler','plmysql_validator');")
    assert out.strip() == "3", "expected 3 handler functions, got %r" % out

    # 能以 plmysql 创建并执行函数（走 PG 协议，此时用 plpgsql 语法）
    cluster.psql("""
        CREATE FUNCTION t001_add(a int, b int) RETURNS int
        LANGUAGE plmysql AS $$ BEGIN RETURN a + b; END $$;
    """)
    out = cluster.psql("SELECT t001_add(2, 3);")
    assert out.strip() == "5", "expected 5, got %r" % out

    # 与 plpgsql 是相互独立的两个语言，plpgsql 未被破坏
    cluster.psql("""
        CREATE FUNCTION t001_mul(a int, b int) RETURNS int
        LANGUAGE plpgsql AS $$ BEGIN RETURN a * b; END $$;
    """)
    out = cluster.psql("SELECT t001_mul(2, 3);")
    assert out.strip() == "6", "plpgsql regression: expected 6, got %r" % out

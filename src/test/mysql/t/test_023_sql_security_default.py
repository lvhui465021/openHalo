"""MySQL 5.7 默认 SQL SECURITY 是 DEFINER，不是 PostgreSQL 原生的 INVOKER。

MySQL 5.7 Reference Manual 13.1.16（SQL SECURITY Characteristic）：
`CREATE PROCEDURE`/`CREATE FUNCTION` 不写 `SQL SECURITY` 子句时，例程按
DEFINER 语义执行。openHalo 的 `SQL SECURITY DEFINER`/`INVOKER` 子句本身
一直是原样透传给 PostgreSQL 原生 `CREATE FUNCTION` 的 `SECURITY DEFINER`/
`INVOKER`（映射到 `pg_proc.prosecdef`），这条链路是对的；缺的只是「不写该
子句时」的默认值——PostgreSQL 原生默认 `prosecdef = false`（INVOKER），
之前 plmysql 直接继承了这个默认，而不是 MySQL 自己的 DEFINER 默认。

本次只补上这一个默认值缺口（`mys_apply_default_sql_security()`，见
`mys_gram.y`），不涉及 DEFINER='user'@'host' 用户名到 pg_proc 属主
（owner）的映射——那是一个更大、涉及权限模型的独立话题，故意没有一并做。
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _prosecdef(cluster, proname):
    out = cluster.psql(
        "SELECT prosecdef FROM pg_proc WHERE proname='%s';" % proname)
    return out.strip()


def run(cluster):
    # 不写 SQL SECURITY：默认必须是 DEFINER（prosecdef = t）
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t023_default_proc",
         "CREATE PROCEDURE t023_default_proc() BEGIN SELECT 1; END")
    assert _prosecdef(cluster, "t023_default_proc") == "t", \
        "PROCEDURE with no SQL SECURITY clause must default to DEFINER"

    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t023_default_func",
         "CREATE FUNCTION t023_default_func() RETURNS INT "
         "BEGIN RETURN 1; END")
    assert _prosecdef(cluster, "t023_default_func") == "t", \
        "FUNCTION with no SQL SECURITY clause must default to DEFINER"

    # MySQL 单语句体 "RETURN expr" 形态（一个独立的语法分支）同样要默认 DEFINER
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t023_default_return",
         "CREATE FUNCTION t023_default_return() RETURNS INT RETURN 1")
    assert _prosecdef(cluster, "t023_default_return") == "t", \
        "one-statement RETURN form must also default to DEFINER"

    # 显式 SQL SECURITY INVOKER：必须继续尊重显式声明，不被默认值覆盖
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t023_explicit_invoker",
         "CREATE PROCEDURE t023_explicit_invoker() SQL SECURITY INVOKER "
         "BEGIN SELECT 1; END")
    assert _prosecdef(cluster, "t023_explicit_invoker") == "f", \
        "explicit SQL SECURITY INVOKER must not be overridden by the default"

    # 显式 SQL SECURITY DEFINER：同样必须原样生效（结果和默认值一样，但走的是
    # 显式分支，不是默认值分支，用来确认两条路径不冲突）
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t023_explicit_definer",
         "CREATE PROCEDURE t023_explicit_definer() SQL SECURITY DEFINER "
         "BEGIN SELECT 1; END")
    assert _prosecdef(cluster, "t023_explicit_definer") == "t", \
        "explicit SQL SECURITY DEFINER must still work"

    # 例程仍然按创建者执行（DEFINER='user'@'host' 只是元数据，见模块文档）：
    # 默认变成 DEFINER 之后，例程调用不应该因为身份变化而报错或行为不同——
    # 单会话下创建者和调用者是同一个角色，prosecdef 打开与否对结果透明。
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t023_default_func()")
            assert cur.fetchone() == (1,)
            cur.execute("SELECT t023_default_return()")
            assert cur.fetchone() == (1,)

"""MySQL 5.7 默认 SQL SECURITY 是 DEFINER——但 plmysql 例程不再用 prosecdef 承载它。

MySQL 5.7 Reference Manual 13.1.16(SQL SECURITY Characteristic):不写
`SQL SECURITY` 子句的例程按 DEFINER 语义执行。openHalo 最初的做法是把该
默认映射为 PostgreSQL 原生 `SECURITY DEFINER`(`mys_apply_default_sql_security()`
补 `security=true` 选项,落 `pg_proc.prosecdef`)。

但 PostgreSQL 的 `ExecuteCallStmt()` 对 prosecdef 例程强制 atomic 执行,
例程体内 COMMIT/ROLLBACK 永远报 1105(兼容报告的 C2 规则 2),而真实 MySQL
的 DEFINER 只是权限检查身份,没有这种安全上下文栈限制。因此现在
`mys_plmysql_redirect_sql_security()`(mys_utility.c)在 CREATE 分发点把
plmysql 例程的 SQL SECURITY 特性改存为 "plmysql" security label 的
`plmysql.sql_security=DEFINER/INVOKER` 条目,`pg_proc.prosecdef` 恒为
false;运行期由 `plmysql_switch_to_routine_definer()`(pl_handler.c)按
definer 元数据切换/恢复有效用户。非 plmysql 例程(如 MySQL 协议下显式
`LANGUAGE plpgsql`)不受影响,仍走原生 prosecdef——所以文法层的默认值
补丁(`mys_apply_default_sql_security()`)保留不动。

DEFINER 身份语义本身(CURRENT_USER() 报 definer、1449、1227)见 test_037。
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


def _label(cluster, proname):
    out = cluster.psql(
        "SELECT label FROM pg_seclabel s JOIN pg_proc p ON p.oid = s.objoid "
        "WHERE p.proname = '%s' AND s.provider = 'plmysql';" % proname)
    return out


def run(cluster):
    # 不写 SQL SECURITY:默认必须是 DEFINER——现在由 label 承载,
    # 而 prosecdef 必须保持 false(否则 CALL 会被强制 atomic,C2 规则 2)。
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t023_default_proc",
         "CREATE PROCEDURE t023_default_proc() BEGIN SELECT 1; END")
    assert _prosecdef(cluster, "t023_default_proc") == "f", \
        "plmysql PROCEDURE must not carry prosecdef (forces atomic CALL)"
    assert "plmysql.sql_security=DEFINER" in _label(cluster, "t023_default_proc"), \
        "PROCEDURE with no SQL SECURITY clause must default to DEFINER (label)"

    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t023_default_func",
         "CREATE FUNCTION t023_default_func() RETURNS INT "
         "BEGIN RETURN 1; END")
    assert _prosecdef(cluster, "t023_default_func") == "f", \
        "plmysql FUNCTION must not carry prosecdef (forces atomic CALL)"
    assert "plmysql.sql_security=DEFINER" in _label(cluster, "t023_default_func"), \
        "FUNCTION with no SQL SECURITY clause must default to DEFINER (label)"

    # MySQL 单语句体 "RETURN expr" 形态(一个独立的语法分支)同样要默认 DEFINER
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t023_default_return",
         "CREATE FUNCTION t023_default_return() RETURNS INT RETURN 1")
    assert _prosecdef(cluster, "t023_default_return") == "f", \
        "one-statement RETURN form must not carry prosecdef either"
    assert "plmysql.sql_security=DEFINER" in _label(cluster, "t023_default_return"), \
        "one-statement RETURN form must also default to DEFINER (label)"

    # 显式 SQL SECURITY INVOKER:必须继续尊重显式声明,不被默认值覆盖
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t023_explicit_invoker",
         "CREATE PROCEDURE t023_explicit_invoker() SQL SECURITY INVOKER "
         "BEGIN SELECT 1; END")
    assert _prosecdef(cluster, "t023_explicit_invoker") == "f", \
        "explicit SQL SECURITY INVOKER must keep prosecdef=false"
    assert "plmysql.sql_security=INVOKER" in _label(cluster, "t023_explicit_invoker"), \
        "explicit SQL SECURITY INVOKER must be recorded in the label"

    # 显式 SQL SECURITY DEFINER:同样走 label(与默认同值,但走显式分支)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t023_explicit_definer",
         "CREATE PROCEDURE t023_explicit_definer() SQL SECURITY DEFINER "
         "BEGIN SELECT 1; END")
    assert _prosecdef(cluster, "t023_explicit_definer") == "f", \
        "explicit SQL SECURITY DEFINER must also stay off prosecdef (C2)"
    assert "plmysql.sql_security=DEFINER" in _label(cluster, "t023_explicit_definer"), \
        "explicit SQL SECURITY DEFINER must be recorded in the label"

    # 例程仍然按创建者/definer 身份执行,单会话下创建者和调用者是同一
    # 角色,调用结果不受影响。
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t023_default_func()")
            assert cur.fetchone() == (1,)
            cur.execute("SELECT t023_default_return()")
            assert cur.fetchone() == (1,)

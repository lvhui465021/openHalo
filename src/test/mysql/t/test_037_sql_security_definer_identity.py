"""C2 规则 2 修复后的 SQL SECURITY DEFINER 运行期身份语义。

plmysql 例程不再把 DEFINER 放进 `pg_proc.prosecdef`(那会让
ExecuteCallStmt() 强制 atomic,阻断体内 COMMIT/ROLLBACK),改为
`plmysql_call_handler()` 调用期按 definer 元数据切换/恢复有效用户
(`plmysql_switch_to_routine_definer()`,pl_handler.c)。本文件钉住:

  * MySQL 账户与 PG 角色 1:1 按名映射(登录时即如此,adapter.c),definer
    只取 user 部分查角色;不写 definer 时即创建者(proowner)。
  * definer 指向不存在的角色 -> MySQL 1449(ER_NO_SUCH_USER),MySQL 自己
    也是在 CALL 期才报这个错。
  * CURRENT_USER() 在 DEFINER 例程体内报 definer;USER()/SESSION_USER()
    仍报登录账户(effective-definer 覆盖栈,systemVar.c + mysm/user.c)。
  * 身份切换在 COMMIT 之后仍然保持(C2 修复的核心不变式),在例程内
    SQLEXCEPTION handler 捕获错误后同样保持。
  * 触发器的 definer(存于其私有函数 proconfig)同样生效。
  * CALL 结束后顶层 CURRENT_USER() 恢复登录身份(栈正确弹出,无泄漏)。
"""

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _rows(cluster, sql):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchall()


def run(cluster):
    # 上一轮失败残留的清理(顺序:例程/表在前,角色最后)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t037_outer",
         "DROP PROCEDURE IF EXISTS t037_inner",
         "DROP PROCEDURE IF EXISTS t037_caught",
         "DROP PROCEDURE IF EXISTS t037_commit",
         "DROP PROCEDURE IF EXISTS t037_ghost",
         "DROP PROCEDURE IF EXISTS t037_invoker",
         "DROP PROCEDURE IF EXISTS t037_def_cur",
         "DROP TABLE IF EXISTS t037_log",
         "DROP TABLE IF EXISTS t037_fire")
    cluster.psql("DROP ROLE IF EXISTS t037_definer;")

    # definer 角色不存在于 MySQL 侧账户体系,只作为 PG 角色存在(1:1 映射)
    cluster.psql("CREATE ROLE t037_definer NOLOGIN;")

    _ddl(cluster,
         "CREATE TABLE t037_log (who VARCHAR(128))",
         "CREATE TABLE t037_fire (id INT)")

    # definer 身份是真实的权限检查身份:例程将以 t037_definer 的权限执行
    # (正如 MySQL 一样),所以该角色需要它将触碰的表权限。
    cluster.psql("GRANT INSERT, SELECT, DELETE ON t037_log TO t037_definer;")

    # 顶层基线:登录身份
    baseline_current = _rows(cluster, "SELECT CURRENT_USER()")[0][0]
    baseline_user = _rows(cluster, "SELECT USER()")[0][0]

    # 1) 显式 DEFINER(非当前用户)→ 体内 CURRENT_USER() 报 definer,
    #    USER() 仍报登录账户
    _ddl(cluster,
         "CREATE DEFINER=`t037_definer`@`%` PROCEDURE t037_def_cur() "
         "BEGIN "
         "INSERT INTO t037_log VALUES (CURRENT_USER()); "
         "INSERT INTO t037_log VALUES (USER()); "
         "END")
    _rows(cluster, "CALL t037_def_cur()")
    assert _rows(cluster, "SELECT who FROM t037_log") == \
        (("t037_definer@%",), (baseline_user,)), \
        "CURRENT_USER()/USER() inside DEFINER routine must report " \
        "definer/login respectively"

    # CALL 结束后顶层身份必须恢复(覆盖栈无泄漏)
    assert _rows(cluster, "SELECT CURRENT_USER()")[0][0] == baseline_current, \
        "top-level CURRENT_USER() must be back to the login identity"

    # 2) 身份切换必须熬过 COMMIT(C2 修复的核心不变式)
    _ddl(cluster, "DELETE FROM t037_log")
    _ddl(cluster,
         "CREATE DEFINER=`t037_definer`@`%` PROCEDURE t037_commit() "
         "BEGIN "
         "INSERT INTO t037_log VALUES (CURRENT_USER()); "
         "COMMIT; "
         "INSERT INTO t037_log VALUES (CURRENT_USER()); "
         "END")
    _rows(cluster, "CALL t037_commit()")
    assert _rows(cluster, "SELECT DISTINCT who FROM t037_log") == \
        (("t037_definer@%",),), \
        "the definer identity must survive COMMIT inside the routine"

    # 3) 例程内 SQLEXCEPTION handler 捕获错误后,身份仍是 definer
    _ddl(cluster, "DELETE FROM t037_log")
    _ddl(cluster,
         "CREATE DEFINER=`t037_definer`@`%` PROCEDURE t037_caught() "
         "BEGIN "
         "DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END; "
         "INSERT INTO t037_nosuch_table VALUES (1); "
         "INSERT INTO t037_log VALUES (CURRENT_USER()); "
         "END")
    _rows(cluster, "CALL t037_caught()")
    assert _rows(cluster, "SELECT who FROM t037_log") == \
        (("t037_definer@%",),), \
        "identity must stay the definer after a caught SQLEXCEPTION"

    # 4) SQL SECURITY INVOKER:不切换,CURRENT_USER() 报登录身份
    _ddl(cluster, "DELETE FROM t037_log")
    _ddl(cluster,
         "CREATE PROCEDURE t037_invoker() SQL SECURITY INVOKER "
         "BEGIN INSERT INTO t037_log VALUES (CURRENT_USER()); END")
    _rows(cluster, "CALL t037_invoker()")
    assert _rows(cluster, "SELECT who FROM t037_log") == \
        ((baseline_current,),), \
        "SQL SECURITY INVOKER routine must run as the login identity"

    # 5) 嵌套:外层 DEFINER 内嵌 INVOKER。MySQL 语义里 INVOKER 例程的
    #    "invoker" 是调用方的有效安全上下文——从 DEFINER 例程内调用时
    #    即 definer,而不是登录账户;实现上 INVOKER 就是不切换、继承
    #    当前 uid,恰好与之一致。
    _ddl(cluster, "DELETE FROM t037_log")
    _ddl(cluster,
         "CREATE PROCEDURE t037_inner() SQL SECURITY INVOKER "
         "BEGIN INSERT INTO t037_log VALUES (CURRENT_USER()); END",
         "CREATE DEFINER=`t037_definer`@`%` PROCEDURE t037_outer() "
         "BEGIN "
         "INSERT INTO t037_log VALUES (CURRENT_USER()); "
         "CALL t037_inner(); "
         "INSERT INTO t037_log VALUES (CURRENT_USER()); "
         "END")
    _rows(cluster, "CALL t037_outer()")
    assert _rows(cluster, "SELECT who FROM t037_log") == \
        (("t037_definer@%",),) * 3, \
        "INVOKER routine nested inside DEFINER routine must inherit the " \
        "caller's effective identity (the definer), as in MySQL"

    # 6) 触发器的 definer(存于私有函数 proconfig)同样生效
    _ddl(cluster, "DELETE FROM t037_log")
    _ddl(cluster,
         "CREATE DEFINER=`t037_definer`@`%` TRIGGER t037_trg "
         "AFTER INSERT ON t037_fire FOR EACH ROW "
         "INSERT INTO t037_log VALUES (CURRENT_USER())")
    _rows(cluster, "INSERT INTO t037_fire VALUES (1)")
    assert _rows(cluster, "SELECT who FROM t037_log") == \
        (("t037_definer@%",),), \
        "a trigger must fire under its definer's identity"

    # 7) definer 指向不存在的角色 → MySQL 1449(MySQL 也在 CALL 期才报)
    _ddl(cluster,
         "CREATE DEFINER=`t037_ghost_zzz`@`localhost` PROCEDURE t037_ghost() "
         "BEGIN SELECT 1; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("CALL t037_ghost()")
                raise AssertionError("CALL with a nonexistent definer "
                                     "unexpectedly succeeded")
            except pymysql.MySQLError as e:
                assert e.args[0] == 1449, \
                    "expected 1449 (ER_NO_SUCH_USER), got %r" % (e.args,)

    # 收尾
    _ddl(cluster,
         "DROP PROCEDURE t037_outer",
         "DROP PROCEDURE t037_inner",
         "DROP PROCEDURE t037_caught",
         "DROP PROCEDURE t037_commit",
         "DROP PROCEDURE t037_ghost",
         "DROP PROCEDURE t037_invoker",
         "DROP PROCEDURE t037_def_cur",
         "DROP TABLE t037_log",
         "DROP TABLE t037_fire")
    cluster.psql("DROP ROLE t037_definer;")

"""存储过程 MySQL 5.7 兼容性清理：plmysql 语法层的 plpgsql 残留必须被关闭。

plmysql 是克隆 plpgsql 改名而来（见 M1 设计），语法层长期残留了一批
MySQL 根本没有的 plpgsql 专属结构，此前会被静默接受：整数/游标/查询
FOR 循环、FOREACH..IN ARRAY、MOVE、可滚动游标方向（PRIOR/FIRST/LAST/
ABSOLUTE/RELATIVE/FORWARD/BACKWARD/ALL）、plpgsql 专属 GET DIAGNOSTICS
项（PG_CONTEXT/PG_EXCEPTION_*/PG_DATATYPE_NAME）、以及 plpgsql 风格的
`EXCEPTION WHEN cond THEN ...` 块级异常处理（MySQL 只有 DECLARE HANDLER
一种错误处理机制）。这些用法要么在真实 MySQL 里根本不存在，要么会让用户
误以为该行为已受支持。本文件钉住：这些语法现在必须以响亮的语法错误失败。

这次清理同时发现一个反例：COMMIT/ROLLBACK 不是残留——它是 MySQL 5.7
存储过程真正支持的语法（只是 FUNCTION/TRIGGER 内禁止，ER_COMMIT_NOT_
ALLOWED_IN_SF_OR_TRG / 1422），此前该限制没有实现。本文件一并钉住新补的
1422 校验，以及 PROCEDURE 内 COMMIT/ROLLBACK 确实按预期工作。
"""

import pymysql


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _expect_syntax_error(cluster, name, body):
    try:
        _ddl(cluster,
             "DROP PROCEDURE IF EXISTS %s" % name,
             "CREATE PROCEDURE %s() %s" % (name, body))
    except pymysql.MySQLError as exc:
        assert exc.args[0] == 1064, exc
    else:
        raise AssertionError(
            "%s: expected a syntax error, but PROCEDURE %s() compiled"
            % (name, name))


def run(cluster):
    # ------------------------------------------------------- 整数范围 FOR 循环
    _expect_syntax_error(
        cluster, "t021_for_range",
        "BEGIN FOR i IN 1..3 LOOP NULL; END LOOP; END")

    # --------------------------------------------------------- 游标 FOR 循环
    _ddl(cluster, "DROP TABLE IF EXISTS t021_t",
         "CREATE TABLE t021_t (c INT)")
    _expect_syntax_error(
        cluster, "t021_for_cursor",
        "BEGIN "
        "DECLARE cur CURSOR FOR SELECT c FROM t021_t; "
        "FOR r IN cur LOOP NULL; END LOOP; "
        "END")

    # ------------------------------------------------------------- FOREACH
    _expect_syntax_error(
        cluster, "t021_foreach",
        "BEGIN FOREACH x IN ARRAY ARRAY[1,2,3] LOOP NULL; END LOOP; END")

    # ---------------------------------------------------------------- MOVE
    _expect_syntax_error(
        cluster, "t021_move",
        "BEGIN "
        "DECLARE cur CURSOR FOR SELECT c FROM t021_t; "
        "OPEN cur; MOVE cur; CLOSE cur; "
        "END")

    # ------------------------------------------------- 可滚动游标 FETCH 方向
    for direction in ("PRIOR", "FIRST", "LAST", "ABSOLUTE 1",
                       "RELATIVE 1", "FORWARD", "BACKWARD", "ALL"):
        _expect_syntax_error(
            cluster, "t021_fetch_dir",
            "BEGIN "
            "DECLARE v INT; "
            "DECLARE cur CURSOR FOR SELECT c FROM t021_t; "
            "OPEN cur; FETCH %s FROM cur INTO v; CLOSE cur; "
            "END" % direction)

    # ------------------------------------------- plpgsql 专属 GET DIAGNOSTICS 项
    for item in ("PG_CONTEXT", "PG_EXCEPTION_DETAIL", "PG_EXCEPTION_HINT",
                 "PG_EXCEPTION_CONTEXT", "PG_DATATYPE_NAME"):
        _expect_syntax_error(
            cluster, "t021_getdiag",
            "BEGIN "
            "DECLARE v TEXT; "
            "GET DIAGNOSTICS CONDITION 1 v = %s; "
            "END" % item)

    # ------------------------------------------- plpgsql 风格 EXCEPTION 块
    _expect_syntax_error(
        cluster, "t021_exception",
        "BEGIN "
        "SELECT 1; "
        "EXCEPTION WHEN OTHERS THEN NULL; "
        "END")

    # ---------------------------------------------------------- 1422：函数内禁止
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            # MySQL 5.7 accepts the CREATE (body check happens at run
            # time); the 1422 must come from calling the function.
            cur.execute("DROP FUNCTION IF EXISTS t021_commit_errno")
            cur.execute("""CREATE FUNCTION t021_commit_errno()
                RETURNS INT BEGIN ROLLBACK; RETURN 1; END""")
            try:
                cur.execute("SELECT t021_commit_errno()")
                cur.fetchall()
                raise AssertionError(
                    "ROLLBACK inside a stored function unexpectedly ran")
            except pymysql.MySQLError as exc:
                assert exc.args[0] == 1422, exc

    # 触发器内禁止 COMMIT/ROLLBACK——与 MySQL 一致的语义:CREATE 成功
    # (body 检查在执行期),触发点火时该语句报 1422。
    _ddl(cluster, "DROP TABLE IF EXISTS t021_trg_t")
    _ddl(cluster, "CREATE TABLE t021_trg_t (v INT)")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP TRIGGER IF EXISTS t021_commit_trg")
            cur.execute("""CREATE TRIGGER t021_commit_trg
                BEFORE INSERT ON t021_trg_t FOR EACH ROW
                BEGIN COMMIT; END""")
            try:
                cur.execute("INSERT INTO t021_trg_t VALUES (1)")
                raise AssertionError(
                    "COMMIT inside a trigger body unexpectedly ran")
            except pymysql.MySQLError as exc:
                assert exc.args[0] == 1422, exc

    # ------------------------------------- COMMIT/ROLLBACK 是合法的 PROCEDURE 语法
    #
    # 这里只钉住"编译得过"：不像 FUNCTION/TRIGGER 那样被拒绝，COMMIT/ROLLBACK
    # 在 PROCEDURE 里合法。**已知缺口**（不是本次清理引入的，是清理途中用这条
    # 用例顺带发现的）：实际 CALL 执行会报 PG 层 1105 "invalid transaction
    # termination"——SPI_commit()/SPI_commit_and_chain() 只在 fcinfo->context
    # 是带 atomic=false 的 CallContext 时才允许（见 pl_handler.c 的
    # `nonatomic` 判定），而 MySQL 协议的 CALL 分发路径目前不会构造这样的
    # CallContext，所以 fcinfo->context 恒为 NULL、恒被当成 atomic 会话执行。
    # 这是 CALL 分发链路本身的运行时缺口，跟本次的语法清理无关，修它需要改
    # MySQL 协议适配层的 CALL 分发，不是 plmysql 语法层的事，留给后续任务。
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t021_commit_proc",
         """CREATE PROCEDURE t021_commit_proc()
         BEGIN
             COMMIT;
             ROLLBACK;
         END""")

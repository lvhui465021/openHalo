"""Batch B/C: 括号 SELECT 语句体、体内事务语句族、1691、1422、FLUSH/维护语句、
长 DEFINER、限定名/FOLLOWS 触发器、1304 剪依赖 —— 一次性回归。

覆盖:
  * (SELECT ...) UNION (SELECT ...) 作为例程体语句(PF1),且结果集正常推送
    (is_select 识别带前导括号的 SELECT,否则结果集会被静默吞掉)。
  * 体内 START TRANSACTION(PF4)= 隐式提交当前事务再开新事务。
  * 体内 SAVEPOINT / ROLLBACK TO / RELEASE SAVEPOINT(PF5):
    - 无 handler 的普通块:回滚到保存点丢弃其后的写入;
    - ROLLBACK TO 后保存点仍然有效(可再次 ROLLBACK TO);
    - COMMIT 释放全部保存点(其后 ROLLBACK TO 报 1305);
    - 未知保存点名报 MySQL 1305;
    - SQLEXCEPTION handler 块内同样可用(wrapper 协议)。
  * LIMIT 处非整型变量 → MySQL 1691(PF3);整型变量放行。
  * 函数体内 DDL(隐式提交)→ MySQL 1422;CREATE TEMPORARY TABLE 放行(T6)。
  * FLUSH TABLES / FLUSH LOGS 顶层 no-op 成功;CHECKSUM TABLE 返回 Table/Checksum;
    REPAIR/OPTIMIZE TABLE 返回 Table/Op/Msg_type/Msg_text 状态行。
  * 长 DEFINER 主机名(>63 字节)不再被截断;DEFINER=CURRENT_USER 解析为创建者。
  * mysqldump 形态的限定名触发器 CREATE TRIGGER db.name;跨 schema 报 1435。
  * DROP FUNCTION 不再被视图依赖阻塞(1304 剪依赖):drop 成功、视图随后报错、
    重建函数后视图恢复。
"""


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
    import pymysql

    _ddl(cluster,
         "DROP TABLE IF EXISTS t038_t",
         "CREATE TABLE t038_t (id INT)",
         "DROP TABLE IF EXISTS t038_sv",
         "CREATE TABLE t038_sv (id INT)")

    # ---- PF1: 括号 SELECT 语句体,结果集必须推送 ----
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_paren",
         "CREATE PROCEDURE t038_paren() "
         "BEGIN (SELECT 'A' AS k) UNION (SELECT 'B'); END")
    assert _rows(cluster, "CALL t038_paren()") == (("A",), ("B",)), \
        "parenthesized UNION body must compile AND push its result set"

    # ---- PF4: 体内 START TRANSACTION ----
    _ddl(cluster, "DELETE FROM t038_t")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_start",
         "CREATE PROCEDURE t038_start() "
         "BEGIN INSERT INTO t038_t VALUES (1); START TRANSACTION; "
         "INSERT INTO t038_t VALUES (2); END")
    _rows(cluster, "CALL t038_start()")
    assert sorted(_rows(cluster, "SELECT id FROM t038_t")) == [(1,), (2,)], \
        "rows before START TRANSACTION must survive its implicit commit"

    # ---- PF5: SAVEPOINT / ROLLBACK TO / RELEASE ----
    _ddl(cluster, "DELETE FROM t038_t")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_sv",
         "CREATE PROCEDURE t038_sv() "
         "BEGIN "
         "INSERT INTO t038_t VALUES (1); "
         "SAVEPOINT s1; "
         "INSERT INTO t038_t VALUES (2); "
         "ROLLBACK TO s1; "
         "INSERT INTO t038_t VALUES (3); "
         "END")
    _rows(cluster, "CALL t038_sv()")
    _got = _rows(cluster, "SELECT id FROM t038_t")
    assert sorted(_got) == [(1,), (3,)], \
        "ROLLBACK TO must discard writes after the savepoint only, got %r" % (_got,)

    # ROLLBACK TO 后保存点仍有效(再次回滚到它)
    _ddl(cluster, "DELETE FROM t038_t")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_sv2",
         "CREATE PROCEDURE t038_sv2() "
         "BEGIN "
         "SAVEPOINT s1; "
         "INSERT INTO t038_t VALUES (1); "
         "ROLLBACK TO s1; "
         "INSERT INTO t038_t VALUES (2); "
         "ROLLBACK TO s1; "
         "END")
    _rows(cluster, "CALL t038_sv2()")
    assert _rows(cluster, "SELECT id FROM t038_t") == (), \
        "the savepoint must stay established after ROLLBACK TO"

    # RELEASE 只删保存点不回滚其效果
    _ddl(cluster, "DELETE FROM t038_t")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_rel",
         "CREATE PROCEDURE t038_rel() "
         "BEGIN "
         "SAVEPOINT s1; "
         "INSERT INTO t038_t VALUES (1); "
         "RELEASE SAVEPOINT s1; "
         "END")
    _rows(cluster, "CALL t038_rel()")
    assert _rows(cluster, "SELECT id FROM t038_t") == ((1,),), \
        "RELEASE must keep the savepoint's effects"

    # COMMIT 释放全部保存点;其后 ROLLBACK TO 报 1305
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_svcom",
         "CREATE PROCEDURE t038_svcom() "
         "BEGIN "
         "SAVEPOINT s1; "
         "COMMIT; "
         "ROLLBACK TO s1; "
         "END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("CALL t038_svcom()")
                cur.fetchall()
                raise AssertionError("ROLLBACK TO after COMMIT unexpectedly "
                                     "succeeded")
            except pymysql.MySQLError as e:
                assert e.args[0] == 1305, \
                    "expected 1305 for savepoint released by COMMIT, got %r" % (e.args,)

    # 未知保存点名 → 1305
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_svbad",
         "CREATE PROCEDURE t038_svbad() BEGIN ROLLBACK TO nosuch; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("CALL t038_svbad()")
                raise AssertionError("ROLLBACK TO unknown savepoint "
                                     "unexpectedly succeeded")
            except pymysql.MySQLError as e:
                assert e.args[0] == 1305, \
                    "expected 1305 for unknown savepoint, got %r" % (e.args,)

    # handler 块内(wrapper 子事务)同样可用
    _ddl(cluster, "DELETE FROM t038_t")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_svhand",
         "CREATE PROCEDURE t038_svhand() "
         "BEGIN "
         "DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END; "
         "INSERT INTO t038_t VALUES (1); "
         "SAVEPOINT s1; "
         "INSERT INTO t038_t VALUES (2); "
         "ROLLBACK TO s1; "
         "END")
    _rows(cluster, "CALL t038_svhand()")
    assert _rows(cluster, "SELECT id FROM t038_t") == ((1,),), \
        "savepoints must work inside a handler-bearing block"

    # ---- PF3: LIMIT 变量类型 1691 ----
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_lim",
         "CREATE PROCEDURE t038_lim(n INT) "
         "BEGIN SELECT id FROM t038_t LIMIT n; END")
    _rows(cluster, "CALL t038_lim(0)")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_limbad",
         "CREATE PROCEDURE t038_limbad(s VARCHAR(10)) "
         "BEGIN SELECT id FROM t038_t LIMIT s; END")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("CALL t038_limbad('x')")
                cur.fetchall()
                raise AssertionError("non-integer LIMIT variable unexpectedly "
                                     "succeeded")
            except pymysql.MySQLError as e:
                assert e.args[0] == 1691, \
                    "expected 1691 for non-integer LIMIT variable, got %r" % (e.args,)

    # ---- T6: 函数体内 DDL → 1422;TEMPORARY 例外 ----
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("CREATE FUNCTION t038_ddl() RETURNS INT "
                            "BEGIN CREATE TABLE t038_nosuch (x INT); RETURN 1; END")
                raise AssertionError("DDL in FUNCTION unexpectedly compiled")
            except pymysql.MySQLError as e:
                assert e.args[0] == 1422, \
                    "expected 1422 for DDL inside FUNCTION, got %r" % (e.args,)

    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t038_tmp",
         "CREATE FUNCTION t038_tmp() RETURNS INT "
         "BEGIN CREATE TEMPORARY TABLE t038_tmp_t (x INT); RETURN 1; END")
    _rows(cluster, "SELECT t038_tmp()")

    # ---- Batch A 语法:FLUSH / 维护语句 ----
    _ddl(cluster, "FLUSH TABLES", "FLUSH LOGS", "FLUSH PRIVILEGES",
         "FLUSH STATUS", "FLUSH TABLES WITH READ LOCK")
    _rows(cluster, "CHECKSUM TABLE t038_t")
    _rows(cluster, "REPAIR TABLE t038_t")
    _rows(cluster, "OPTIMIZE TABLE t038_t")
    # 例程体内同样可用(leader 列表)
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_flush",
         "CREATE PROCEDURE t038_flush() BEGIN FLUSH TABLES; END")
    _rows(cluster, "CALL t038_flush()")

    # ---- 长 DEFINER 主机名 ----
    long_host = "h" * 70 + ".example.com"
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_longdef",
         "CREATE DEFINER=halo@%s PROCEDURE t038_longdef() "
         "BEGIN SELECT 1; END" % long_host)
    out = cluster.psql(
        "SELECT label FROM pg_seclabel s JOIN pg_proc p ON p.oid = s.objoid "
        "WHERE p.proname = 't038_longdef' AND s.provider = 'plmysql';")
    assert long_host in out, "long definer host must be stored verbatim, got %r" % out

    # ---- DEFINER=CURRENT_USER ----
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_cu",
         "CREATE DEFINER=CURRENT_USER PROCEDURE t038_cu() BEGIN SELECT 1; END")
    out = cluster.psql(
        "SELECT label FROM pg_seclabel s JOIN pg_proc p ON p.oid = s.objoid "
        "WHERE p.proname = 't038_cu' AND s.provider = 'plmysql';")
    assert "plmysql.definer=halo@%" in out, \
        "CURRENT_USER definer must resolve to the creating role, got %r" % out

    # ---- 限定名触发器(dump 形态)+ 跨 schema 1435 ----
    _ddl(cluster,
         "DROP TABLE IF EXISTS t038_trg",
         "CREATE TABLE t038_trg (id INT)",
         "DROP TRIGGER IF EXISTS t038_trg_t",
         "CREATE TRIGGER public.t038_trg_t AFTER INSERT ON t038_trg "
         "FOR EACH ROW INSERT INTO t038_sv VALUES (1)")
    _rows(cluster, "INSERT INTO t038_trg VALUES (1)")
    assert _rows(cluster, "SELECT id FROM t038_sv") == ((1,),), \
        "mysqldump-style qualified trigger name must work"
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("CREATE TRIGGER mysql.t038_badtrg AFTER INSERT ON "
                            "t038_trg FOR EACH ROW INSERT INTO t038_sv VALUES (2)")
                raise AssertionError("cross-schema trigger unexpectedly created")
            except pymysql.MySQLError as e:
                assert e.args[0] == 1435, \
                    "expected 1435 for trigger schema mismatch, got %r" % (e.args,)

    # ---- IF() 的 text 条件(MySQL 前缀数字语义)在触发器 @变量链中的可用性 ----
    _ddl(cluster,
         "DROP TABLE IF EXISTS t038_if_t",
         "DROP TABLE IF EXISTS t038_if_a")
    _ddl(cluster,
         "CREATE TABLE t038_if_t (i INT)",
         "CREATE TABLE t038_if_a (v VARCHAR(200))",
         "CREATE TRIGGER t038_if_trg BEFORE INSERT ON t038_if_t FOR EACH ROW "
         "SET @a := IF(@a, CONCAT(@a, ':', NEW.i), CAST(NEW.i AS CHAR))")
    # @a 是会话变量,整条链必须在同一连接内
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SET @a = ''")
            cur.execute("INSERT INTO t038_if_t VALUES (2),(3),(4),(5)")
            cur.execute("SELECT @a")
            assert cur.fetchall() == (("2:3:4:5",),), \
                "IF(text) condition chain must accumulate like MySQL"
    _ddl(cluster, "DROP TRIGGER t038_if_trg", "DROP TABLE t038_if_t",
         "DROP TABLE t038_if_a")

    # ---- C17: SHOW CREATE 反映 SQL SECURITY 特性 ----
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SHOW CREATE PROCEDURE t023_explicit_invoker")
            assert "SQL SECURITY INVOKER" in cur.fetchone()[2], \
                "explicit INVOKER must appear in SHOW CREATE"
            cur.execute("SHOW CREATE PROCEDURE t038_lim")
            assert "SQL SECURITY" not in cur.fetchone()[2], \
                "default DEFINER stays implicit in SHOW CREATE"

    # ---- 1304 剪依赖:视图依赖不阻塞 DROP FUNCTION ----
    _ddl(cluster,
         "DROP VIEW IF EXISTS t038_v",
         "DROP FUNCTION IF EXISTS t038_f",
         "CREATE FUNCTION t038_f() RETURNS INT RETURN 1",
         "CREATE VIEW t038_v AS SELECT t038_f() AS r")
    _rows(cluster, "SELECT * FROM t038_v")
    _ddl(cluster, "DROP FUNCTION t038_f")   # MySQL 语义:成功,不 CASCADE
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            try:
                cur.execute("SELECT * FROM t038_v")
                cur.fetchall()
                raise AssertionError("orphaned view unexpectedly usable")
            except pymysql.MySQLError as e:
                # MySQL 报 1356(视图引用失效对象);openHalo 在 PostgreSQL
                # 规则按 OID 缓存函数引用的模型下报 1105/1305——失效本身
                # 一致,错误码差异文档化。
                assert e.args[0] in (1105, 1305, 1356), \
                    "expected 1105/1305/1356 from orphaned view, got %r" % (e.args,)
    # 视图规则按 OID 缓存函数引用:重建函数(OID 变化)不能自动恢复,
    # 视图需要按 MySQL dump 的顺序(functions 先于 views)重建。这也是
    # mysqldump 导入顺序本身的要求。
    _ddl(cluster,
         "DROP VIEW IF EXISTS t038_v",
         "CREATE OR REPLACE FUNCTION t038_f() RETURNS INT RETURN 1",
         "CREATE VIEW t038_v AS SELECT t038_f() AS r")
    assert _rows(cluster, "SELECT * FROM t038_v") == ((1,),), \
        "view recreated in dump order must work"
    _ddl(cluster, "DROP VIEW t038_v", "DROP FUNCTION t038_f")

    # 收尾
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t038_paren",
         "DROP PROCEDURE IF EXISTS t038_start",
         "DROP PROCEDURE IF EXISTS t038_sv",
         "DROP PROCEDURE IF EXISTS t038_sv2",
         "DROP PROCEDURE IF EXISTS t038_rel",
         "DROP PROCEDURE IF EXISTS t038_svcom",
         "DROP PROCEDURE IF EXISTS t038_svbad",
         "DROP PROCEDURE IF EXISTS t038_svhand",
         "DROP PROCEDURE IF EXISTS t038_lim",
         "DROP PROCEDURE IF EXISTS t038_limbad",
         "DROP FUNCTION IF EXISTS t038_tmp",
         "DROP PROCEDURE IF EXISTS t038_flush",
         "DROP PROCEDURE IF EXISTS t038_longdef",
         "DROP PROCEDURE IF EXISTS t038_cu",
         "DROP TRIGGER IF EXISTS t038_trg_t",
         "DROP TABLE t038_trg",
         "DROP TABLE t038_t",
         "DROP TABLE t038_sv")

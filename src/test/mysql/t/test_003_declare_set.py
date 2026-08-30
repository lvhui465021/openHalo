"""MySQL SQL/PSM 块结构：BEGIN...END、DECLARE 局部变量、SET 赋值、IF/RETURN。

`_ddl()`/连接都带 dbname="public"：不带的话 MySQL 协议连接的 search_path
只剩 {mysql, pg_catalog}，任何 CREATE 都会先报 1049 "no schema has been
selected to create in"（既有行为，见 test_002 的说明），会在到达 plmysql
语法层之前就失败，掩盖本测试真正要钉的 DECLARE/SET 语法错误。

**观测方式的说明（Task 5 修改）**：本文件在 Task 4 创建时，用的是
`CALL p()` + 过程体里一句裸 `SELECT w;` 来读出变量值。那条路在 M1 走不通——
「过程体里的 SELECT 把结果集回传给客户端」是 MySQL 的多结果集语义，设计文档
把它排在 **M5**（见 `docs/superpowers/specs/...` 的 M5「CALL OUT 回写 + 多结果
集」）。继承自 plpgsql 的执行器对没有 INTO 的 SELECT 曾一律报
"query has no destination for result data"。所以本文件大多数用例改用两种 M1
已支持的观测方式：存储函数用 `RETURN` 回值，存储过程写进表再读回来。
`_bare_select_returns_resultset()` 单独验证 M5 补上的裸 SELECT 回传语义本身。
"""

import pymysql


# --------------------------------------------------------------------- helpers

def _ddl(cluster, *statements):
    """在 MySQL 协议连接上依次执行若干条 DDL。"""
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _scalar(cluster, sql, args=None):
    """执行一条查询并取回第一行第一列。"""
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            row = cur.fetchone()
    return row


def _func(cluster, name, sig, rettype, body, call, want, why=""):
    """建一个存储函数、调用它、断言返回值。"""
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS %s" % name,
         "CREATE FUNCTION %s(%s) RETURNS %s\n%s" % (name, sig, rettype, body))
    row = _scalar(cluster, call)
    assert row == (want,), "%s%s: expected %r, got %r" % (
        name, (" (%s)" % why) if why else "", (want,), row)


def _expect_error(cluster, tag, ddl, fragment):
    """这条 DDL 必须失败，且错误信息里要出现 fragment。"""
    try:
        _ddl(cluster, ddl)
    except pymysql.err.MySQLError as e:
        assert fragment in str(e), \
            "%s: expected an error mentioning %r, got %r" % (tag, fragment, e)
    else:
        raise AssertionError("%s: expected this to be rejected, but it was "
                             "accepted" % tag)


# ------------------------------------------------------------- the tests

def _basic_declare_set(cluster):
    """本文件最初要钉的东西：DECLARE 两个变量、SET 赋值、结果是 42。

    过程与函数各来一遍，两条路径（CALL / SELECT f()）都要通。
    """
    # 存储过程：把结果写进表再读回来
    _ddl(cluster,
         "DROP TABLE IF EXISTS t003_out",
         "CREATE TABLE t003_out (v INT)",
         "DROP PROCEDURE IF EXISTS t003_p",
         """
         CREATE PROCEDURE t003_p()
         BEGIN
             DECLARE v INT DEFAULT 1;
             DECLARE w INT;
             SET w = v + 41;
             INSERT INTO t003_out VALUES (w);
         END
         """)
    _ddl(cluster, "CALL t003_p()")
    row = _scalar(cluster, "SELECT v FROM t003_out")
    assert row == (42,), "CALL t003_p(): expected (42,), got %r" % (row,)

    # 存储函数：同样的块，用 RETURN 回值
    _func(cluster, "t003_f42", "", "INT", """
         BEGIN
             DECLARE v INT DEFAULT 1;
             DECLARE w INT;
             SET w = v + 41;
             RETURN w;
         END
         """, "SELECT t003_f42()", 42)


def _bare_select_returns_resultset(cluster):
    """过程体里的裸 SELECT（无 INTO）把结果集直接回传给客户端（M5 语义）。

    这条用例曾经是「已知限制」：M1 阶段裸 SELECT 必须响亮报错
    "query has no destination for result data"。M5 补上了多结果集回传后，
    这里改为断言 CALL 能读到那一行数据。
    """
    _ddl(cluster, "DROP PROCEDURE IF EXISTS t003_baresel")
    _ddl(cluster, """
         CREATE PROCEDURE t003_baresel()
         BEGIN
             DECLARE v INT DEFAULT 42;
             SELECT v;
         END
         """)
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t003_baresel()")
            assert cur.fetchall() == ((42,),), \
                "expected the bare SELECT's row back from CALL"


def _if_elseif_else(cluster):
    """IF/ELSEIF/ELSE 继承自克隆，块结构改写后仍须可用。

    ELSEIF 是 MySQL 的拼写。Task 4 把 "elseif" 放进了**保留字**表（K_ELSEIF），
    核心扫描器会先命中它，克隆来的 K_ELSIF 产生式因此不再接受这个拼写；
    pl_gram.y 的 elseif_key 把两种拼写都收下。两种都测，混用也测。
    """
    _ddl(cluster, "DROP FUNCTION IF EXISTS t003_if")
    _ddl(cluster, """
         CREATE FUNCTION t003_if(n INT) RETURNS TEXT
         BEGIN
             DECLARE r TEXT;
             IF n < 0 THEN
                 SET r = 'neg';
             ELSEIF n = 0 THEN
                 SET r = 'zero';
             ELSE
                 SET r = 'pos';
             END IF;
             RETURN r;
         END
         """)
    for arg, want in ((-1, 'neg'), (0, 'zero'), (1, 'pos')):
        row = _scalar(cluster, "SELECT t003_if(%s)", (arg,))
        assert row == (want,), "t003_if(%d): expected %r, got %r" % (arg, want, row)

    # ELSIF（plpgsql 拼写）仍然接受，且两种拼写可以混在同一条链里
    _ddl(cluster, "DROP FUNCTION IF EXISTS t003_elsif")
    _ddl(cluster, """
         CREATE FUNCTION t003_elsif(n INT) RETURNS TEXT
         BEGIN
             DECLARE r TEXT;
             IF n = 0 THEN SET r = 'a';
             ELSEIF n = 1 THEN SET r = 'b';
             ELSIF  n = 2 THEN SET r = 'c';
             ELSEIF n = 3 THEN SET r = 'd';
             ELSE SET r = 'e';
             END IF;
             RETURN r;
         END
         """)
    for arg, want in ((0, 'a'), (1, 'b'), (2, 'c'), (3, 'd'), (4, 'e')):
        row = _scalar(cluster, "SELECT t003_elsif(%s)", (arg,))
        assert row == (want,), "t003_elsif(%d): expected %r, got %r" % (arg, want, row)


def _return_stmt(cluster):
    """RETURN（存储函数）继承自克隆。"""
    _func(cluster, "t003_f", "n INT", "INT", """
         BEGIN
             DECLARE d INT DEFAULT 10;
             RETURN n * d;
         END
         """, "SELECT t003_f(4)", 40)


def _multi_variable_declare(cluster):
    """一条 DECLARE 声明多个同类型变量。"""
    # 三个变量都拿到了 DEFAULT
    _func(cluster, "t003_multi", "", "INT", """
         BEGIN
             DECLARE a, b, c INT DEFAULT 5;
             SET a = a + b + c;
             RETURN a;
         END
         """, "SELECT t003_multi()", 15)

    # 三个是彼此独立的 datum，不是同一个变量的别名：改掉 a、b 之后 c 不受影响
    _func(cluster, "t003_multi_distinct", "", "INT", """
         BEGIN
             DECLARE a, b, c INT DEFAULT 5;
             SET a = 1;
             SET b = 2;
             RETURN a * 100 + b * 10 + c;
         END
         """, "SELECT t003_multi_distinct()", 125,
          why="a,b,c must be three distinct datums")

    # 不带 DEFAULT 时每个都是 NULL
    _func(cluster, "t003_multi_null", "", "INT", """
         BEGIN
             DECLARE a, b INT;
             SET a = 1;
             IF b IS NULL THEN
                 SET a = a + 10;
             END IF;
             RETURN a;
         END
         """, "SELECT t003_multi_null()", 11)

    # 带 typmod 的类型也要逐个变量各拿一份类型结构
    _func(cluster, "t003_multi_typmod", "", "TEXT", """
         BEGIN
             DECLARE a, b VARCHAR(8) DEFAULT 'xy';
             RETURN concat('[', a, '|', b, ']');
         END
         """, "SELECT t003_multi_typmod()", '[xy|xy]')


def _block_entry_initialization(cluster):
    """不变量 3：plmysql_add_initdatums 必须收齐**本块**声明的每一个变量。

    重置（add_initdatums(NULL)）放在 pl_block 的 K_BEGIN 之后、每块一次；收集
    放在 mysql_decl_sect、每块一次。若把重置改成「每条 DECLARE 一次」，第二条
    DECLARE 就会把第一条声明的变量挤出 initvarnos，它们在块入口不再被初始化，
    下面这条会变成 NULL。
    """
    _func(cluster, "t003_initvars", "", "INT", """
         BEGIN
             DECLARE a INT DEFAULT 1;
             DECLARE b INT DEFAULT 2;
             DECLARE c INT DEFAULT 4;
             DECLARE d INT DEFAULT 8;
             RETURN a + b + c + d;
         END
         """, "SELECT t003_initvars()", 15,
          why="every DECLARE of the block must reach initvarnos")

    # 后一条 DECLARE 的默认值可以引用前一条声明的变量：块入口按声明顺序逐个求值
    _func(cluster, "t003_deforder", "", "INT", """
         BEGIN
             DECLARE a INT DEFAULT 3;
             DECLARE b INT DEFAULT a * 10;
             RETURN b;
         END
         """, "SELECT t003_deforder()", 30)

    # 早先这里用 FOR 循环的隐式循环变量验证：语句造出的 datum 不能被算进内层块的
    # initvarnos。FOR/FOREACH 已随存储过程 MySQL 兼容性清理从 plmysql 语法里整体
    # 拿掉（不是 MySQL 语法，见 mys_gram.y 的原文捕获层测试）——清理之后 plmysql
    # 里已经没有任何语句会隐式创建 datum，一切变量都必须走显式 DECLARE，原场景
    # 已经不可能复现。这里改为验证两个紧邻的同级嵌套块互不可见对方声明的变量，
    # 钉的还是同一条不变式：每个 pl_block 入口的 initvarnos 重置。
    _func(cluster, "t003_datumscope", "", "INT", """
         BEGIN
             DECLARE a INT DEFAULT 5;
             BEGIN
                 DECLARE i INT DEFAULT 3;
                 SET a = a + i;
             END;
             BEGIN
                 DECLARE b INT DEFAULT 100;
                 SET a = a + b;
             END;
             RETURN a;
         END
         """, "SELECT t003_datumscope()", 108)


def _nested_blocks_and_scoping(cluster):
    """不变量 1 + 2 + 3 一起钉：嵌套块里同名变量的解析。

    三层嵌套、每层各声明一个 x，从里往外读。它同时要求：
      * 每个 pl_block 的 plmysql_ns_push/plmysql_ns_pop 恰好配对一次
        （少 pop 一次，出块后读到的还是内层的 x，结果会变成 333）；
      * 声明名字时 plmysql_IdentifierLookup 已经切到 IDENTIFIER_LOOKUP_DECLARE
        （否则内层的 `DECLARE x` 里的 x 会被扫描器解析成外层变量的 T_DATUM，
        decl_varname 收不下，直接语法错误）；
      * 每层各自的 x 在本层入口拿到自己的 DEFAULT。
    """
    _func(cluster, "t003_shadow", "", "INT", """
         BEGIN
             DECLARE r INT DEFAULT 0;
             DECLARE x INT DEFAULT 1;
             BEGIN
                 DECLARE x INT DEFAULT 2;
                 BEGIN
                     DECLARE x INT DEFAULT 3;
                     SET r = r * 10 + x;
                 END;
                 SET r = r * 10 + x;
             END;
             SET r = r * 10 + x;
             RETURN r;
         END
         """, "SELECT t003_shadow()", 321,
          why="ns push/pop must pair per block; 333 means a pop was lost")

    # 声明的名字与函数参数同名：同样要求声明期扫描器不做变量解析
    _func(cluster, "t003_shadow_param", "n INT", "INT", """
         BEGIN
             DECLARE n INT DEFAULT 7;
             RETURN n;
         END
         """, "SELECT t003_shadow_param(1)", 7,
          why="a DECLARE may shadow a parameter of the same name")

    # 20 层嵌套：命名空间栈在深度上也要配平，出来之后最外层的变量还看得见
    _ddl(cluster, "DROP FUNCTION IF EXISTS t003_deep")
    _ddl(cluster,
         "CREATE FUNCTION t003_deep() RETURNS INT BEGIN DECLARE x INT DEFAULT 7; "
         + "BEGIN DECLARE y INT DEFAULT 2; END; " * 20
         + "RETURN x; END")
    row = _scalar(cluster, "SELECT t003_deep()")
    assert row == (7,), "t003_deep: expected (7,), got %r" % (row,)

    # 带标签的块：标签进命名空间，可以用 label.var 限定读写
    _func(cluster, "t003_label", "", "INT", """
         BEGIN
             DECLARE x INT DEFAULT 1;
             <<blk>>
             BEGIN
                 DECLARE x INT DEFAULT 2;
                 DECLARE y INT;
                 SET y = blk.x + 10;
                 SET blk.x = 99;
                 RETURN y + x;
             END blk;
         END
         """, "SELECT t003_label()", 111,
          why="qualified name resolution reads the namespace stack")


def _empty_sections(cluster):
    """mysql_decl_sect 与 proc_sect 都可为空——这是块结构改写最可能引入
    bison 冲突的组合，四种空/非空组合都要能编译并跑起来。"""
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t003_e00",
         "CREATE PROCEDURE t003_e00() BEGIN END",
         "CALL t003_e00()")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t003_e01",
         "CREATE PROCEDURE t003_e01() BEGIN NULL; END",
         "CALL t003_e01()")
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t003_e10",
         "CREATE PROCEDURE t003_e10() BEGIN DECLARE a INT DEFAULT 1; END",
         "CALL t003_e10()")
    _func(cluster, "t003_e11", "", "INT", """
         BEGIN
             DECLARE a INT DEFAULT 1;
             RETURN a;
         END
         """, "SELECT t003_e11()", 1)
    # 空块套空块
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t003_e_nest",
         "CREATE PROCEDURE t003_e_nest() BEGIN BEGIN END; END",
         "CALL t003_e_nest()")


def _must_fail_loudly(cluster):
    """这些写法必须被拒绝，且错误要说清楚是什么问题。"""
    # MySQL 要求 DECLARE 只能出现在块首；块结构本身把这一点钉死了
    _expect_error(cluster, "DECLARE after a statement", """
         CREATE PROCEDURE t003_bad1()
         BEGIN
             DECLARE a INT DEFAULT 1;
             SET a = 2;
             DECLARE b INT;
         END
         """, "syntax error")

    # SET 的目标必须是已知变量，且报错要点名
    _expect_error(cluster, "SET on unknown name",
                  "CREATE PROCEDURE t003_bad2() BEGIN SET nosuchvar = 1; END",
                  '"nosuchvar" is not a known variable')

    # 同一条 DECLARE 里重名
    _expect_error(cluster, "duplicate name within one DECLARE",
                  "CREATE PROCEDURE t003_bad3() BEGIN DECLARE a, a INT; END",
                  "duplicate declaration")

    # 跨 DECLARE 重名（这条是克隆来的 decl_varname 本来就管的）
    _expect_error(cluster, "duplicate name across DECLAREs",
                  "CREATE PROCEDURE t003_bad4() "
                  "BEGIN DECLARE a INT; DECLARE a INT; END",
                  "duplicate declaration")

    # SET 现在是保留字（MySQL 里也是），不能拿来当变量名
    _expect_error(cluster, "variable named SET",
                  "CREATE PROCEDURE t003_bad5() BEGIN DECLARE set INT; END",
                  "syntax error")


def run(cluster):
    _basic_declare_set(cluster)
    _bare_select_returns_resultset(cluster)
    _if_elseif_else(cluster)
    _return_stmt(cluster)
    _multi_variable_declare(cluster)
    _block_entry_initialization(cluster)
    _nested_blocks_and_scoping(cluster)
    _empty_sections(cluster)
    _must_fail_loudly(cluster)

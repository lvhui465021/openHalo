"""sql_mode 位在扫描/解析期真正生效：ANSI_QUOTES、NO_BACKSLASH_ESCAPES、PIPES_AS_CONCAT。

这三个 mode 此前只是被解析进 `mys_sqlMode` 位掩码存起来（供例程 CREATE 时
快照用），但没有任何扫描器/语法层代码真的去读这些位——双引号、反斜杠、`&&`、`||`
的词法/语义完全不受它们影响，本文件前三段钉住修好之后的行为。

`||` 那段还多一个发现：符号 `&&`/`||` 一直是无条件编译成 aux_mysql 的
`mysql.&&`/`mysql.||` 自定义算子族（一批按操作数类型重载的函数，实现 MySQL
"任意值转真值再做布尔运算、结果是整数 0/1" 的语义），这本身是对的、没有改；
唯一的口子是 PIPES_AS_CONCAT 打开后 `||` 应该改邢 MySQL 的 CONCAT 语义——
把符号解析改成显式限定到 `pg_catalog.||` 并把两侧都转成 text，才能不撞上
`mysql.||` 更宽的 anynonarray 重载（否则纯数字或非数字文本两侧会直接报
"operator does not exist"/"Data truncated"，因为落进了布尔 OR 那条路）。
"""

import pymysql


def _scalar(cursor, sql):
    cursor.execute(sql)
    return cursor.fetchone()[0]


def _expect_error(cursor, sql):
    try:
        cursor.execute(sql)
    except pymysql.MySQLError:
        return
    raise AssertionError("expected statement to fail: %s" % sql)


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS t022_t")
            cur.execute("CREATE TABLE t022_t (col INT)")
            cur.execute("INSERT INTO t022_t VALUES (7)")

            # --------------------------------------------------- ANSI_QUOTES
            cur.execute("SET SESSION sql_mode = ''")
            # 默认：双引号是字符串
            assert _scalar(cur, 'SELECT "abc"') == "abc"

            cur.execute("SET SESSION sql_mode = 'ANSI_QUOTES'")
            # ANSI_QUOTES 打开后：双引号是分隔标识符，不再是字符串
            assert _scalar(cur, 'SELECT "col" FROM t022_t') == 7
            # 单引号字符串不受影响
            assert _scalar(cur, "SELECT 'abc'") == "abc"
            # 反引号标识符不受影响，双引号/反引号两种写法都能引用同一列
            assert _scalar(cur, "SELECT `col` FROM t022_t") == 7
            # 加倍转义（"" 表示字面双引号）在标识符模式下依然生效
            cur.execute('DROP TABLE IF EXISTS "t022_""weird"')
            cur.execute('CREATE TABLE "t022_""weird" (v INT)')
            cur.execute('INSERT INTO "t022_""weird" VALUES (9)')
            assert _scalar(cur, 'SELECT v FROM "t022_""weird"') == 9
            cur.execute('DROP TABLE "t022_""weird"')

            cur.execute("SET SESSION sql_mode = ''")
            # 关掉之后恢复默认：双引号又是字符串
            assert _scalar(cur, 'SELECT "abc"') == "abc"

            # ---------------------------------------------- NO_BACKSLASH_ESCAPES
            # 默认：反斜杠是转义引导符，\n 是换行符（长度 1）
            assert _scalar(cur, r"SELECT '\n'") == "\n"
            assert _scalar(cur, r'SELECT "\n"') == "\n"

            cur.execute("SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'")
            # 打开后：反斜杠是普通字符，\n 是两个字符（长度 2）
            assert _scalar(cur, r"SELECT '\n'") == "\\n"
            assert _scalar(cur, r'SELECT "\n"') == "\\n"
            # 加倍转义（'' / ""）依然是写字面引号的办法，不受影响
            assert _scalar(cur, "SELECT 'it''s'") == "it's"

            cur.execute("SET SESSION sql_mode = ''")
            assert _scalar(cur, r"SELECT '\n'") == "\n"

            # -------------------------------------------------- PIPES_AS_CONCAT
            # 默认（MySQL 5.7 的默认 sql_mode 不含 PIPES_AS_CONCAT）：
            # || 是布尔 OR，&& 恒是布尔 AND（不受 sql_mode 影响）
            assert _scalar(cur, "SELECT (1 = 1) || (1 = 0)")
            assert not _scalar(cur, "SELECT (1 = 1) && (1 = 0)")
            assert _scalar(cur, "SELECT (0 = 1) || (2 = 2)")
            _expect_error(cur, "SELECT 'a' || 'b'")

            cur.execute("SET SESSION sql_mode = 'PIPES_AS_CONCAT'")
            # 打开后：|| 变成字符串拼接，&& 仍然是布尔 AND
            assert _scalar(cur, "SELECT 'a' || 'b'") == "ab"
            assert not _scalar(cur, "SELECT (1 = 1) && (1 = 0)")
            # MySQL 的 CONCAT 风格 || 两侧都会被隐式转成字符串，不限于文本
            assert _scalar(cur, "SELECT 1 || 2") == "12"
            assert _scalar(cur, "SELECT 1 || 'x'") == "1x"
            # NULL 传播：任一侧为 NULL，结果是 NULL（跟 MySQL CONCAT/|| 一致）
            assert _scalar(cur, "SELECT NULL || 'x'") is None

            cur.execute("SET SESSION sql_mode = ''")
            assert _scalar(cur, "SELECT (1 = 1) || (1 = 0)")
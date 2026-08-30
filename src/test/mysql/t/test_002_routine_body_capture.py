"""MySQL 协议下裸 BEGIN...END 过程体可被捕获并存入 pg_proc.prosrc。

覆盖方式说明（fix round 3 起）：过程体用例按**结构类别**组织，不是逐个枚举
想得到的写法。前三轮的回归都是「判据本身有个错误前提，在某个没枚举到的形状/
数字上翻车」，所以这里刻意让同一类结构在参数上连续取值（括号里 0/1/2/3 个顶层
逗号、1/2/3 层括号嵌套……），而不是只挑一两个代表。

`_ddl()` 传 dbname="public"：MySQL 协议把客户端请求的 "database" 当作 PG schema
装进 search_path，不传时 search_path 只剩 {mysql, pg_catalog}，任何 CREATE 都会
报 1049 "no schema has been selected to create in"。这是既有行为，与语法改动无关。
"""


def _ddl(cluster, *statements):
    """在 MySQL 协议连接上依次执行若干条 DDL。"""
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def _expect_unterminated(cluster, cases):
    """钉住已知局限：这些写法必须以「响亮的报错」失败。

    捕获层的记账保证是单向的（跟踪深度只会 >= 真实深度），所以判不出来时只可能
    读到输入末尾报 unterminated，不可能提前截断成一段「看起来正常」的过程体。
    这里把这一点钉死：将来谁把这些用例「修好」，也必须保持失败是响亮的，绝不能
    变成静默截断。
    """
    import pymysql

    cluster.psql("ALTER ROLE halo SET check_function_bodies = off;")
    try:
        for i, (tag, body) in enumerate(cases):
            name = "t002_lim%d" % i
            try:
                _ddl(cluster, "CREATE PROCEDURE %s() %s" % (name, body))
            except pymysql.err.MySQLError as e:
                assert "unterminated routine body" in str(e), \
                    "%s: expected a loud 'unterminated routine body', got %r" % (
                        tag, e)
            else:
                out = cluster.psql(
                    "SELECT prosrc FROM pg_proc WHERE proname='%s';" % name)
                _ddl(cluster, "DROP PROCEDURE IF EXISTS %s" % name)
                assert out.strip() == body, \
                    "%s: silently truncated body: %r" % (tag, out.strip())
                raise AssertionError(
                    "%s: now captured correctly -- good, but move it out of the "
                    "known-limitation list" % tag)
    finally:
        cluster.psql("ALTER ROLE halo RESET check_function_bodies;")


def _check_bodies(cluster, cases, validate=True):
    """建过程并逐字比对 prosrc。

    validate=False 时临时关掉 check_function_bodies：M1 阶段 plmysql 语法仍等价
    于 plpgsql，MySQL 独有的语法（WHILE..DO、REPEAT..UNTIL、DECLARE..HANDLER）
    编译不过。这些用例要钉的是 mys_gram.y 的原文捕获，不是 plmysql 能不能编译。
    GUC 走 ALTER ROLE + 新建连接下发：MySQL 协议的 SET 不认这个 PG GUC
    （会报 1292 Unknown system variable）。
    """
    if not validate:
        cluster.psql("ALTER ROLE halo SET check_function_bodies = off;")
    try:
        for i, (tag, body) in enumerate(cases):
            name = "t002_c%s%d" % ("v" if validate else "n", i)
            _ddl(cluster,
                 "DROP PROCEDURE IF EXISTS %s" % name,
                 "CREATE PROCEDURE %s() %s" % (name, body))
            out = cluster.psql(
                "SELECT prosrc FROM pg_proc WHERE proname='%s';" % name)
            assert out.strip() == body, \
                "%s: prosrc not verbatim\n  expected: %r\n  got:      %r" % (
                    tag, body, out.strip())
    finally:
        if not validate:
            cluster.psql("ALTER ROLE halo RESET check_function_bodies;")


def run(cluster):
    # ---------------------------------------------------------------- 目录属性
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_p",
         "CREATE PROCEDURE t002_p() BEGIN NULL; END")

    # 语言必须是 plmysql，不是 sql
    out = cluster.psql(
        "SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang "
        "WHERE p.proname='t002_p';")
    assert out.strip() == "plmysql", "expected plmysql, got %r" % out

    # prosrc 必须是原文（含 BEGIN/END），不是被解析后重构的
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_p';")
    src = out.strip()
    assert src.upper().startswith("BEGIN"), "prosrc should start with BEGIN: %r" % src
    assert src.upper().rstrip(";").endswith("END"), "prosrc should end with END: %r" % src
    assert src == "BEGIN NULL; END", "body not verbatim: %r" % src

    # prokind 是 procedure
    out = cluster.psql("SELECT prokind FROM pg_proc WHERE proname='t002_p';")
    assert out.strip() == "p", "expected prokind=p, got %r" % out

    # 供下面子查询条件引用（只编译不执行，但保持语句本身合法）
    _ddl(cluster,
         "DROP TABLE IF EXISTS t002_t",
         "CREATE TABLE t002_t (c int)")

    # ------------------------------------------------ 块结构：开/闭必须逐层配对
    _check_bodies(cluster, [
        ("bare block",       "BEGIN NULL; END"),
        ("nested BEGIN",     "BEGIN BEGIN NULL; END; NULL; END"),
        ("BEGIN x3",         "BEGIN BEGIN BEGIN NULL; END; END; NULL; END"),
        # CASE 语句以 END CASE 收尾，CASE 表达式以裸 END 收尾——两种都要算对
        ("CASE stmt",
         "BEGIN CASE WHEN 1 = 1 THEN NULL; ELSE NULL; END CASE; NULL; END"),
        ("CASE expr",
         "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END; NULL; END"),
        ("CASE expr AS alias",
         "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END AS x; NULL; END"),
        ("CASE expr nested",
         "BEGIN SELECT CASE WHEN 1 = 1 THEN CASE WHEN 2 = 2 THEN 1 ELSE 2 END "
         "ELSE 3 END; NULL; END"),
        ("IF nested in IF",
         "BEGIN IF 1 = 1 THEN IF 2 = 2 THEN NULL; END IF; ELSE NULL; END IF; NULL; END"),
        # plpgsql 风格的 WHILE：WHILE 与 LOOP 相邻出现，只有一个 END LOOP。
        # plmysql 的 stmt_while 同时保留 MySQL 拼写（WHILE..DO..END WHILE）和
        # 这种 plpgsql 拼写，两者都编译得过。
        ("WHILE..LOOP (plpgsql)",
         "BEGIN WHILE 1 = 0 LOOP NULL; END LOOP; NULL; END"),
    ])

    # plpgsql 风格的 FOR..LOOP：整数范围/游标/查询 FOR 循环不是 MySQL 语法，
    # 存储过程兼容性清理已经把它从 plmysql 语法里关掉（不像 WHILE 那样保留双
    # 拼写），所以这里必须 validate=False 才能编译过——这条用例钉的是 mys_gram.y
    # 外层原文捕获层对 LOOP/END LOOP 嵌套配对的计数，不是 plmysql 能不能跑 FOR。
    _check_bodies(cluster, [
        ("FOR..LOOP (plpgsql, capture-only)",
         "BEGIN FOR i IN 1..3 LOOP NULL; END LOOP; NULL; END"),
    ], validate=False)

    # ------------------------------------- 语句形式 IF：条件的形状不应影响判定
    #
    # 前三轮的回归都栽在「拿条件的局部形状去猜这是不是函数调用」上：先是看前一个
    # token，再是看 IF 与 '(' 之间有没有空白，再是数括号里的顶层逗号。这里把顶层
    # 逗号数从 0 连续取到 3、括号嵌套从 1 层取到 3 层、并让条件横跨多个括号组，
    # 就是为了让任何「只看第一个括号组内部结构」的判据都必然在其中某一条上暴露。
    _check_bodies(cluster, [
        (tag, "BEGIN IF %s THEN NULL; END IF; NULL; END" % cond)
        for tag, cond in [
            ("no parens",           "1 = 1"),
            ("1 group",             "(1 = 1)"),
            ("2 levels",            "((1 = 1))"),
            ("3 levels",            "(((1 = 1)))"),
            ("groups + AND",        "(1 = 1) AND (2 = 2)"),
            ("groups + OR/AND",     "(1 = 1) OR ((2 = 2) AND (3 = 3))"),
            ("subquery 0 comma",    "(SELECT count(*) FROM t002_t) > 0"),
            ("subquery 1 comma",    "(SELECT x.c FROM t002_t x, t002_t y) > 0"),
            # 2 个顶层逗号 == IF(a,b,c) 的参数个数：round 2 的逗号计数判据死在这里
            ("subquery 2 comma",
             "(SELECT x.c FROM t002_t x, t002_t y, t002_t z) > 0"),
            ("subquery 3 comma",
             "(SELECT x.c FROM t002_t x, t002_t y, t002_t z, t002_t w) > 0"),
            ("row compare 1 comma", "(1, 2) = (1, 2)"),
            ("row compare 2 comma", "(1, 2, 3) = (1, 2, 3)"),
            ("NOT cond",            "NOT (1 = 0)"),
            ("EXISTS subq",         "EXISTS (SELECT 1)"),
            ("NOT EXISTS subq",     "NOT EXISTS (SELECT 1)"),
        ]])

    # ----------------- 表达式里的 IF()/REPEAT()：是函数调用，绝不能被当成开块
    _check_bodies(cluster, [(tag, "BEGIN %s; NULL; END" % expr) for tag, expr in [
        ("IF() tight",       "SELECT IF(1, 2, 3)"),
        ("IF() spaced",      "SELECT IF (1, 2, 3)"),
        ("IF() nested",      "SELECT IF(IF(1, 2, 3), 4, 5)"),
        # 函数调用后面紧跟 THEN：不能被那个 THEN 骗成语句形式
        ("IF() before THEN",
         "SELECT CASE WHEN IF(1, 1, 0) THEN 'y' ELSE 'n' END"),
        ("REPEAT() tight",   "SELECT REPEAT('a', 3)"),
        ("REPEAT() spaced",  "SELECT REPEAT ('a', 3)"),
        ("both in one expr", "SELECT concat(IF(1, 'a', 'b'), REPEAT('c', 2))"),
        # CASE 表达式的 THEN/ELSE 后面跟的是表达式，这里的 IF()/REPEAT() 是函数
        ("IF() after THEN",
         "SELECT CASE WHEN 1 = 1 THEN IF(1, 2, 3) ELSE 0 END"),
        ("REPEAT() after ELSE",
         "SELECT CASE WHEN 1 = 0 THEN 'x' ELSE REPEAT('a', 3) END"),
    ]])

    # ------------------------- IF 作为 DDL 子句修饰符：IF EXISTS / IF NOT EXISTS
    # 这份文法里约 85 处产生式用到它（grep "IF_P EXISTS\|IF_P NOT EXISTS"）
    _check_bodies(cluster, [(tag, "BEGIN %s; NULL; END" % stmt) for tag, stmt in [
        ("DROP TABLE IF EXISTS",     "DROP TABLE IF EXISTS t002_tmp"),
        ("CREATE TABLE IF NOT EX",   "CREATE TABLE IF NOT EXISTS t002_tmp (c int)"),
        ("DROP PROCEDURE IF EXISTS", "DROP PROCEDURE IF EXISTS t002_nosuch"),
        ("DROP INDEX IF EXISTS",     "DROP INDEX IF EXISTS t002_noidx"),
    ]])

    # --------------------------------- MySQL 独有的块语法（plmysql 尚不能编译）
    # Task 5 会真正解析这些；此刻先保证捕获层的配对计数对它们是正确的。
    _check_bodies(cluster, [
        ("WHILE..DO..END WHILE",
         "BEGIN WHILE 1 = 0 DO NULL; END WHILE; NULL; END"),
        ("REPEAT..UNTIL..END REPEAT",
         "BEGIN REPEAT NULL; UNTIL 1 = 1 END REPEAT; NULL; END"),
        ("LOOP..END LOOP + label",
         "BEGIN lbl: LOOP LEAVE lbl; END LOOP lbl; NULL; END"),
        ("labelled BEGIN block",
         "BEGIN lbl: BEGIN NULL; END lbl; NULL; END"),
        ("CASE stmt MySQL form",
         "BEGIN CASE 1 WHEN 1 THEN NULL; ELSE NULL; END CASE; NULL; END"),
        ("WHILE wrapping IF",
         "BEGIN WHILE 1 = 0 DO IF 1 = 1 THEN NULL; END IF; END WHILE; NULL; END"),
        # REPEAT 块里再放一个 REPEAT()/IF() 函数调用
        ("REPEAT block + IF() call",
         "BEGIN REPEAT SELECT IF(1, 2, 3); UNTIL 1 = 1 END REPEAT; NULL; END"),
        ("IF/ELSEIF/ELSE",
         "BEGIN IF 1 = 1 THEN NULL; ELSEIF 2 = 2 THEN NULL; ELSE NULL; "
         "END IF; NULL; END"),
        # DECLARE ... HANDLER FOR <condition> 后面直接跟一条 IF 语句
        ("HANDLER FOR + IF stmt",
         "BEGIN DECLARE CONTINUE HANDLER FOR SQLEXCEPTION "
         "IF 1 = 1 THEN NULL; END IF; NULL; END"),
        ("deep mix",
         "BEGIN BEGIN WHILE 1 = 0 DO REPEAT SELECT IF(1, 2, 3); "
         "UNTIL 1 = 1 END REPEAT; END WHILE; END; NULL; END"),
    ], validate=False)

    # ------------- CASE 表达式的裸 END 后面紧跟 IF/LOOP/WHILE/REPEAT（fix round 4）
    #
    # "END <关键字>" 这两个 token 的相邻关系并不足以证明它是块的闭合符：CASE 表达式
    # 也以裸 END 收尾，而它后面完全可以合法地跟这四个关键字之一——最常见的是不带
    # AS 的列别名（这四个词都在 bare_label_keyword 里）。捕获层靠「本层是否可能有
    # 该种块开着」来分辨，所以这里对四个关键字 × 多种位置连续取值，而不是只挑一两
    # 个写法：任何只看相邻 token 的判据必然在其中某一条上暴露。
    _check_bodies(cluster, [
        (tag.replace("%s", kw), body.replace("%s", kw))
        for kw in ("if", "loop", "while", "repeat")
        for tag, body in [
            ("alias %s bare",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END %s; NULL; END"),
            # AS 形式无歧义，本来就该过；和裸形式放一起才说明差别只在 AS
            ("alias %s AS form",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END AS %s; NULL; END"),
            ("alias %s newline",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END\n  %s; NULL; END"),
            # 别名紧挨着过程体自己的 END（后面没有别的语句垫着）
            ("alias %s last stmt",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END %s; END"),
            ("alias %s then FROM",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END %s FROM t002_t; END"),
            ("alias %s then comma",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END %s, 7 AS y; END"),
            ("alias %s nested CASE",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN CASE WHEN 2 = 2 THEN 1 ELSE 2 END "
             "ELSE 3 END %s; END"),
            ("alias %s in nested BEGIN",
             "BEGIN BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END %s; END; END"),
            ("alias %s x2",
             "BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END %s; "
             "SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END %s; END"),
        ]])

    # 同一层里先有一个同名关键字的其它用法，再出现别名：判定必须按「层」隔离，
    # 用全局计数会在这两条上翻车（函数调用把配额吃掉，别名就被当成闭合符）。
    _check_bodies(cluster, [
        ("IF() then alias if",
         "BEGIN SELECT IF(1, 2, 3); "
         "SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END if; END"),
        ("REPEAT() then alias repeat",
         "BEGIN SELECT REPEAT('a', 3); "
         "SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END repeat; END"),
        ("IF EXISTS then alias if",
         "BEGIN DROP TABLE IF EXISTS t002_tmp; "
         "SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END if; END"),
    ])

    # 别名出现在块里，且块自己的闭合符就在后面：一次误判会连累后面的 END LOOP /
    # END IF，所以这组同时钉住「别名要放行」和「真闭合符要照旧」。
    _check_bodies(cluster, [
        ("alias in LOOP + END LOOP",
         "BEGIN LOOP SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END loop; LEAVE; "
         "END LOOP; END"),
        ("alias in IF + END IF",
         "BEGIN IF 1 = 1 THEN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END if; "
         "END IF; END"),
        ("alias in WHILE + END WHILE",
         "BEGIN WHILE 1 = 0 DO IF 1 = 1 THEN "
         "SELECT CASE WHEN 2 = 2 THEN 1 ELSE 2 END while; END IF; "
         "END WHILE; NULL; END"),
        ("alias in REPEAT + END REPEAT",
         "BEGIN REPEAT SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END repeat; "
         "UNTIL 1 = 1 END REPEAT; END"),
        ("alias in labelled BEGIN",
         "BEGIN lbl: BEGIN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END loop; "
         "END lbl; END"),
    ], validate=False)

    # 本层的计数记的是「可能还开着几个」，不是「一共见过几个」：块闭合掉之后要把
    # 名额还回去，否则同名关键字当块标签出现在本层的裸 END 后面时又会被吞掉。
    # （标签与块关键字同名是很别扭的写法——MySQL 里要写成反引号形式——但它是唯一
    # 能观测到「还名额」这一步的形状，所以留在这里守着。）
    _check_bodies(cluster, [
        ("label loop after END LOOP",
         "BEGIN loop: BEGIN LOOP LEAVE; END LOOP; END loop; NULL; END"),
        ("label if after END IF",
         "BEGIN if: BEGIN IF 1 = 1 THEN NULL; END IF; END if; NULL; END"),
        ("label while after END WHILE",
         "BEGIN while: BEGIN WHILE 1 = 0 DO NULL; END WHILE; END while; "
         "NULL; END"),
        ("label repeat after END REPEAT",
         "BEGIN repeat: BEGIN REPEAT NULL; UNTIL 1 = 1 END REPEAT; END repeat; "
         "NULL; END"),
        ("label loop, no inner LOOP",
         "BEGIN loop: BEGIN NULL; END loop; NULL; END"),
    ], validate=False)

    # 反向：真的闭合符所在层里另有同名关键字的无关用法，闭合读法必须照旧胜出。
    _check_bodies(cluster, [
        ("IF stmt with IF() inside",
         "BEGIN IF 1 = 1 THEN SELECT IF(1, 2, 3); END IF; END"),
        ("IF() before IF stmt",
         "BEGIN SELECT IF(1, 2, 3); IF 1 = 1 THEN NULL; END IF; END"),
        ("IF() x3 before IF stmt",
         "BEGIN SELECT IF(1, 2, 3); SELECT IF(1, 2, 3); SELECT IF(1, 2, 3); "
         "IF 1 = 1 THEN NULL; END IF; END"),
        ("IF EXISTS inside IF stmt",
         "BEGIN IF 1 = 1 THEN DROP TABLE IF EXISTS t002_tmp; END IF; END"),
        ("REPEAT() before REPEAT blk",
         "BEGIN SELECT REPEAT('a', 3); REPEAT NULL; UNTIL 1 = 1 END REPEAT; END"),
        ("END IF x2 sequential",
         "BEGIN IF 1 = 1 THEN NULL; END IF; IF 2 = 2 THEN NULL; END IF; END"),
        ("END IF wrapping BEGIN blk",
         "BEGIN IF 1 = 1 THEN BEGIN NULL; END; END IF; END"),
        ("END IF wrapping CASE stmt",
         "BEGIN IF 1 = 1 THEN CASE WHEN 1 = 1 THEN NULL; ELSE NULL; END CASE; "
         "END IF; END"),
        ("END IF cond is CASE expr",
         "BEGIN IF CASE WHEN 1 = 1 THEN true ELSE false END THEN NULL; END IF; END"),
        ("END REPEAT until CASE expr",
         "BEGIN REPEAT NULL; UNTIL CASE WHEN 1 = 1 THEN true ELSE false END "
         "END REPEAT; NULL; END"),
        ("END WHILE cond CASE expr",
         "BEGIN WHILE CASE WHEN 1 = 1 THEN false ELSE true END DO NULL; "
         "END WHILE; END"),
    ], validate=False)

    # plpgsql 的循环头把条件直接顶在 LOOP 前面，条件又可以是 CASE 表达式，于是
    # "END LOOP" 两个 token 会在没有任何 LOOP 块打开的地方相邻出现。
    _check_bodies(cluster, [
        ("FOR query + CASE expr",
         "BEGIN FOR r IN SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END LOOP NULL; "
         "END LOOP; NULL; END"),
        ("WHILE CASE expr LOOP",
         "BEGIN WHILE CASE WHEN 1 = 1 THEN false ELSE true END LOOP NULL; "
         "END LOOP; NULL; END"),
        ("FOR range + CASE expr",
         "BEGIN FOR i IN 1..CASE WHEN 1 = 1 THEN 3 ELSE 5 END LOOP NULL; "
         "END LOOP; NULL; END"),
        ("FOR range + CASE expr nested",
         "BEGIN BEGIN FOR i IN 1..CASE WHEN 1 = 1 THEN 3 ELSE 5 END LOOP NULL; "
         "END LOOP; END; END"),
    ], validate=False)

    # 每层一份计数，层数不设上限：这条走到 seen[] 的 repalloc 扩容路径
    _check_bodies(cluster, [
        ("BEGIN x20",
         "BEGIN " + "BEGIN " * 20 + "NULL; " + "END; " * 20 + "END"),
        ("CASE expr x20",
         "BEGIN SELECT " + "CASE WHEN 1 = 1 THEN " * 20 + "1" +
         " ELSE 2 END" * 20 + "; END"),
        ("alias at depth 20",
         "BEGIN " + "BEGIN " * 20 +
         "SELECT CASE WHEN 1 = 1 THEN 1 ELSE 2 END loop; " +
         "END; " * 20 + "END"),
    ], validate=False)

    # ------------------------------------------------- 已知局限（必须响亮地失败）
    # 一般形状：某个计数层（BEGIN 或 CASE 表达式开的）里，只要出现过同一个关键字
    # 的未配对用法——函数调用、IF EXISTS、别名，任何会让该层计数非零的写法都算——
    # 紧接着这一层自己的裸 END 后面又跟了同一个关键字，判据就只能取「闭合符」这
    # 一读法，而不是把 END 还给主语法。下面用 CASE 表达式 + IF()/REPEAT() 函数
    # 调用来实例化这个形状（目前只有 CASE 表达式的裸 END 能落进这个位置，见
    # mys_gram.y 里 mys_capture_routine_body 的注释）。详见该函数注释。
    _expect_unterminated(cluster, [
        ("IF() inside + alias if",
         "BEGIN SELECT CASE WHEN 1 = 1 THEN IF(1, 2, 3) ELSE 2 END if; END"),
        ("REPEAT() inside + alias repeat",
         "BEGIN SELECT CASE WHEN 1 = 1 THEN REPEAT('a', 3) ELSE 'b' END repeat; "
         "END"),
    ])

    # ------------------------------------------------------- CREATE FUNCTION 分支
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t002_f",
         "CREATE FUNCTION t002_f() RETURNS INT BEGIN RETURN 1; END")
    out = cluster.psql(
        "SELECT l.lanname, p.prokind, p.prosrc FROM pg_proc p "
        "JOIN pg_language l ON l.oid=p.prolang WHERE p.proname='t002_f';")
    assert out.strip() == "plmysql|f|BEGIN RETURN 1; END", \
        "function body not captured as plmysql: %r" % out

    # ------------------------------------------------- BEGIN ATOMIC 不能被抢走
    # 必须走 MySQL 协议：opt_routine_body 的 BEGIN ATOMIC 分支和裸 BEGIN 捕获
    # 分支只在 mys_gram.y 里共存，psql（PG 协议）根本不经过这份语法。
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t002_atomic",
         "CREATE FUNCTION t002_atomic() RETURNS int LANGUAGE SQL "
         "BEGIN ATOMIC SELECT 1; END")
    out = cluster.psql(
        "SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang "
        "WHERE p.proname='t002_atomic';")
    assert out.strip() == "sql", "BEGIN ATOMIC hijacked by capture path: %r" % out

    # -------------------------------- 收尾 token 必须还给主语法，不能被吞掉
    # 捕获要读到最后那个 END 之后一个 token 才能确定它不是 "END IF"，那个 token
    # 属于过程体之外，必须交还给 bison。这里用带结尾分号的写法钉住这一点。
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_semi",
         "CREATE PROCEDURE t002_semi() BEGIN NULL; END;")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_semi';")
    assert out.strip() == "BEGIN NULL; END", \
        "trailing semicolon leaked into prosrc: %r" % out.strip()

    # 结尾分号后面还有内容时，交还才真正可观测：分号若被吞掉，第二条语句会跟
    # 第一条的 END 粘在一起变成语法错误。用 MULTI_STATEMENTS 连接构造这个场景
    # （cluster.mysql() 不带这个 client flag，所以这里直接建连接）。
    import pymysql

    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_multi1",
         "DROP PROCEDURE IF EXISTS t002_multi2")
    conn = pymysql.connect(
        host="127.0.0.1", port=cluster.mysql_port, user="halo",
        database="public", autocommit=True, charset="utf8mb4",
        client_flag=pymysql.constants.CLIENT.MULTI_STATEMENTS)
    try:
        with conn.cursor() as cur:
            cur.execute("CREATE PROCEDURE t002_multi1() BEGIN NULL; END; "
                        "CREATE PROCEDURE t002_multi2() BEGIN BEGIN NULL; END; END")
    finally:
        conn.close()
    out = cluster.psql(
        "SELECT proname, prosrc FROM pg_proc WHERE proname LIKE 't002\\_multi%' "
        "ORDER BY proname;")
    assert out.split() == ["t002_multi1|BEGIN", "NULL;", "END",
                           "t002_multi2|BEGIN", "BEGIN", "NULL;", "END;", "END"], \
        "statement separator after END was swallowed: %r" % out

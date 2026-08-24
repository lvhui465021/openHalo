"""MySQL 协议下裸 BEGIN...END 过程体可被捕获并存入 pg_proc.prosrc。

此阶段 plmysql 语法仍等价于 plpgsql，因此过程体用两种语法都能解析的写法。

注意所有建过程/建函数的连接都传 dbname="public"：MySQL 协议把客户端请求的
"database" 当作 PG schema 装进 search_path，不传时 search_path 只剩
{mysql, pg_catalog}，任何 CREATE 都会报 1049 "no schema has been selected to
create in"。这是既有行为，与本任务的语法改动无关（在改动前的构建上同样如此）。
"""


def _ddl(cluster, *statements):
    """在 MySQL 协议连接上依次执行若干条 DDL。"""
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
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

    # 嵌套 BEGIN...END 不能提前截断
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_nested",
         "CREATE PROCEDURE t002_nested() BEGIN BEGIN NULL; END; NULL; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_nested';")
    src = out.strip()
    assert src.count("BEGIN") == 2, "nested BEGIN lost: %r" % src
    assert src.upper().rstrip(";").endswith("END"), "truncated at inner END: %r" % src
    # 上面两条断言对「在内层 END 截断」并不敏感（"BEGIN BEGIN NULL; END" 同样满足
    # 二者），真正把它钉死的是这条逐字比对：截断会丢掉尾部的 "; NULL; END"。
    assert src == "BEGIN BEGIN NULL; END; NULL; END", "nested body not verbatim: %r" % src

    # IF(expr,a,b) 函数调用不应被误判为开块
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_iffunc",
         "CREATE PROCEDURE t002_iffunc() BEGIN SELECT IF(1, 2, 3); END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_iffunc';")
    src = out.strip()
    assert src.upper().rstrip(";").endswith("END"), \
        "IF() miscounted as block opener: %r" % src
    assert src == "BEGIN SELECT IF(1, 2, 3); END", "body not verbatim: %r" % src

    # REPEAT(str,n) 函数调用同理（REPEAT 也是块关键字）
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_repeatfunc",
         "CREATE PROCEDURE t002_repeatfunc() BEGIN SELECT REPEAT('a', 3); END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_repeatfunc';")
    src = out.strip()
    assert src == "BEGIN SELECT REPEAT('a', 3); END", \
        "REPEAT() miscounted as block opener: %r" % src

    # 语句形式的 IF ... THEN ... END IF 必须开块，且带括号的条件不能被当成函数调用。
    # 这条是对 IF 判定规则的反向约束：只看「IF 后面是不是 '('」会在这里判错，
    # 提前在 "END IF" 的 END 处收尾。
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_ifstmt",
         "CREATE PROCEDURE t002_ifstmt() "
         "BEGIN IF (1 = 1) THEN NULL; END IF; NULL; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_ifstmt';")
    src = out.strip()
    assert src == "BEGIN IF (1 = 1) THEN NULL; END IF; NULL; END", \
        "IF ... END IF nesting lost: %r" % src

    # CASE 表达式以裸 END 收尾（不是 END CASE），开/闭计数必须自洽
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_caseexpr",
         "DROP TABLE IF EXISTS t002_t",
         "CREATE TABLE t002_t (c int)",
         "CREATE PROCEDURE t002_caseexpr() "
         "BEGIN UPDATE t002_t SET c = CASE WHEN 1 = 1 THEN 1 ELSE 2 END; NULL; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_caseexpr';")
    src = out.strip()
    assert src == ("BEGIN UPDATE t002_t SET c = CASE WHEN 1 = 1 THEN 1 "
                   "ELSE 2 END; NULL; END"), "CASE expression miscounted: %r" % src

    # CASE 表达式的 THEN/ELSE 后面跟的是表达式，不是语句：这里的 IF()/REPEAT()
    # 仍然是函数调用。（fix round 1 / 发现 1：靠「前一个 token 是不是语句起始位置」
    # 判定会在这里判错，THEN 后面的 IF( 被当成开块，depth 多算一层，一路吃到
    # EOF 报 "unterminated routine body: missing END"。）
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_casethenif",
         "CREATE PROCEDURE t002_casethenif() "
         "BEGIN SELECT CASE WHEN 1 = 1 THEN IF(1, 2, 3) ELSE 0 END; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_casethenif';")
    src = out.strip()
    assert src == "BEGIN SELECT CASE WHEN 1 = 1 THEN IF(1, 2, 3) ELSE 0 END; END", \
        "IF() after CASE-expression THEN miscounted: %r" % src

    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_caseelserepeat",
         "CREATE PROCEDURE t002_caseelserepeat() "
         "BEGIN SELECT CASE WHEN 1 = 0 THEN 'x' ELSE REPEAT('a', 3) END; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_caseelserepeat';")
    src = out.strip()
    assert src == ("BEGIN SELECT CASE WHEN 1 = 0 THEN 'x' "
                   "ELSE REPEAT('a', 3) END; END"), \
        "REPEAT() after CASE-expression ELSE miscounted: %r" % src

    # 无空格写法的语句形式 IF(cond) THEN：紧邻的 '(' 让它看起来像函数调用，
    # 但括号组之后跟着 THEN，说明是语句形式。
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_ifnospace",
         "CREATE PROCEDURE t002_ifnospace() "
         "BEGIN IF(1 = 1) THEN NULL; END IF; NULL; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_ifnospace';")
    src = out.strip()
    assert src == "BEGIN IF(1 = 1) THEN NULL; END IF; NULL; END", \
        "IF(cond) THEN misjudged as function call: %r" % src

    # 条件本身以括号子表达式开头的语句形式：IF (SELECT ...) > 0 THEN。
    # 括号组后面不是 THEN，所以「括号组 + 紧跟 THEN」单独一条规则也不够，
    # 必须靠 IF 与 '(' 之间有无空白来判定。
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t002_ifparenexpr",
         "CREATE PROCEDURE t002_ifparenexpr() "
         "BEGIN IF (SELECT count(*) FROM t002_t) > 0 THEN NULL; END IF; NULL; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_ifparenexpr';")
    src = out.strip()
    assert src == ("BEGIN IF (SELECT count(*) FROM t002_t) > 0 THEN NULL; "
                   "END IF; NULL; END"), \
        "IF (subquery) > 0 THEN miscounted: %r" % src

    # fix round 1 / 发现 2：DECLARE ... HANDLER FOR <condition> <stmt>，handler
    # 后面那条语句是 IF ... END IF。它前面是一个 condition 名（标识符），旧的
    # 「语句起始位置」集合里没有它，会漏算一层，END IF 提前把 depth 归零。
    #
    # 这个过程体 plmysql（M1 阶段仍等价于 plpgsql）编译不了，所以临时关掉
    # check_function_bodies —— 本用例要钉的是 mys_gram.y 的原文捕获，不是
    # plmysql 能不能编译 HANDLER。GUC 走 ALTER ROLE + 新建连接下发：MySQL 协议
    # 的 SET 不认这个 PG GUC（会报 1292 Unknown system variable）。
    cluster.psql("ALTER ROLE halo SET check_function_bodies = off;")
    try:
        _ddl(cluster,
             "DROP PROCEDURE IF EXISTS t002_handler",
             "CREATE PROCEDURE t002_handler() BEGIN "
             "DECLARE CONTINUE HANDLER FOR SQLEXCEPTION "
             "IF 1 = 1 THEN NULL; END IF; NULL; END")
    finally:
        cluster.psql("ALTER ROLE halo RESET check_function_bodies;")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_handler';")
    src = out.strip()
    assert src == ("BEGIN DECLARE CONTINUE HANDLER FOR SQLEXCEPTION "
                   "IF 1 = 1 THEN NULL; END IF; NULL; END"), \
        "IF after HANDLER FOR miscounted: %r" % src

    # CREATE FUNCTION 分支同样要走捕获路径
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t002_f",
         "CREATE FUNCTION t002_f() RETURNS INT BEGIN RETURN 1; END")
    out = cluster.psql(
        "SELECT l.lanname, p.prokind, p.prosrc FROM pg_proc p "
        "JOIN pg_language l ON l.oid=p.prolang WHERE p.proname='t002_f';")
    assert out.strip() == "plmysql|f|BEGIN RETURN 1; END", \
        "function body not captured as plmysql: %r" % out

    # BEGIN ATOMIC（PostgreSQL 标准 SQL 函数体）不能被捕获路径抢走。
    # 必须走 MySQL 协议：opt_routine_body 的 BEGIN ATOMIC 分支和新增的裸 BEGIN
    # 捕获分支只在 mys_gram.y 里共存，psql（PG 协议）根本不经过这份语法。
    _ddl(cluster,
         "DROP FUNCTION IF EXISTS t002_atomic",
         "CREATE FUNCTION t002_atomic() RETURNS int LANGUAGE SQL "
         "BEGIN ATOMIC SELECT 1; END")
    out = cluster.psql(
        "SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang "
        "WHERE p.proname='t002_atomic';")
    assert out.strip() == "sql", "BEGIN ATOMIC hijacked by capture path: %r" % out

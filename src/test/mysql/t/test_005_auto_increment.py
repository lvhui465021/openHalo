"""AUTO_INCREMENT 列的自增值在 MySQL 协议下建表插入后仍然正确。

这是 M1 完成标准（docs/superpowers/plans/2026-08-22-m1-plmysql-skeleton.md
「M1 完成标准」小节最后一条）里此前唯一一条零自动化覆盖的验收条件——只在
Task 6 手工跑过一次 throwaway 脚本（见 task-6-report.md「AUTO_INCREMENT
regression check」小节），没有沉淀成常驻回归。

回归的对象是 `src/backend/parser/mysql/mys_parse_utilcmd.c:849-938` 的
AUTO_INCREMENT 触发器链（`createAutoIncrementTriggerFunc`/`createTrigger`/
`createSeq` 等）：这条链跟本分支改动的 `mys_gram.y`/`pl_gram.y` 语法本身无关
——它在 C 里直接拼 `CreateFunctionStmt`，`language` 硬编码为 `plpgsql`，运行在
MySQL 协议会话里——但它正是「不碰 `src/pl/plpgsql/`」这条全局约束存在的唯一
生产依赖理由。这个测试的职责就是证明本分支没有回归它，不求更多。
"""


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS t005_ai")
            cur.execute(
                "CREATE TABLE t005_ai (id INT AUTO_INCREMENT PRIMARY KEY, "
                "v INT)")
            cur.execute("INSERT INTO t005_ai (v) VALUES (10)")
            cur.execute("INSERT INTO t005_ai (v) VALUES (20)")

    # 读回走 PG 协议：跟 test_002/003 一样，只是用来独立验证落盘数据，跟
    # AUTO_INCREMENT 本身走哪条协议无关。
    out = cluster.psql("SELECT id, v FROM t005_ai ORDER BY id;")
    rows = [line.split("|") for line in out.strip().splitlines()]
    assert rows == [["1", "10"], ["2", "20"]], \
        "AUTO_INCREMENT values: expected [(1,10),(2,20)], got %r" % rows

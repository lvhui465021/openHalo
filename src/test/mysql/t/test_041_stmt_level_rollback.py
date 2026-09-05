"""事务块内的语句级回滚(MySQL 语义)。

MySQL:autocommit=0 / 显式事务内,一条语句失败只回滚该语句自身——
事务与其先前语句的效果保留,事务继续可用。PostgreSQL 原生行为是整个
事务进入 aborted 状态,后续语句全部被拒
("current transaction is aborted")。

修复:MySQL 协议 + 事务块内,每条语句(事务控制语句除外)包在内部
子事务里执行(standard_exec_simple_query);成功则 Release,失败则
RollbackAndReleaseCurrentSubTransaction 并把错误按 MySQL 协议发给客户端,
然后继续事务内的下一条语句。
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    import pymysql

    _ddl(cluster, "DROP TABLE IF EXISTS t041_srb")

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SET autocommit = 0")
            cur.execute("CREATE TABLE t041_srb (id INT PRIMARY KEY, v VARCHAR(20))")
            cur.execute("COMMIT")

            # 显式事务:成功、失败、成功、COMMIT
            cur.execute("START TRANSACTION")
            cur.execute("INSERT INTO t041_srb VALUES (1, 'keep')")
            cur.execute("INSERT INTO t041_srb VALUES (2, 'first')")
            try:
                cur.execute("INSERT INTO t041_srb VALUES (2, 'dup')")
                raise AssertionError("duplicate insert unexpectedly succeeded")
            except pymysql.err.IntegrityError as e:
                assert e.args[0] == 1062, e
            # 失败后事务必须仍然可用
            cur.execute("INSERT INTO t041_srb VALUES (3, 'also-keep')")
            cur.execute("COMMIT")
            cur.execute("SELECT id, v FROM t041_srb ORDER BY id")
            assert cur.fetchall() == ((1, 'keep'), (2, 'first'), (3, 'also-keep')), \
                "failed statement must roll back itself only"

            # 失败语句抛出的错误是 MySQL 1062(不是 PG 23505/25P02)
            cur.execute("START TRANSACTION")
            cur.execute("DELETE FROM t041_srb WHERE id = 3")
            try:
                cur.execute("INSERT INTO t041_srb VALUES (1, 'dup')")
            except pymysql.err.IntegrityError as e:
                assert e.args[0] == 1062, e
            cur.execute("ROLLBACK")
            cur.execute("SELECT id FROM t041_srb ORDER BY id")
            assert cur.fetchall() == ((1,), (2,), (3,))

            cur.execute("DROP TABLE t041_srb")

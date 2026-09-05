"""REPLACE INTO 必须触发 DELETE 触发器(MySQL 语义)。

MySQL 的 REPLACE INTO 命中唯一键冲突时会删除旧行再插入新行——该删除
必须 fire BEFORE/AFTER DELETE 触发器。此前 openHalo 把 REPLACE 降级为
自定义 ONCONFLICT_REPLACE,执行器里只做了堆删除(ExecDeleteAct),绕过
了触发器机制;且 planner 侧 infer_arbiter_indexes 对无 inference 的
ON CONFLICT 返回 NIL,REPLACE 的冲突预检查空转,直接撞 1062。

修复:planner 侧为 DO REPLACE 推断全部唯一(非部分、立即检查)索引作
arbiter;executor 侧冲突分支镜像 ExecDelete 序列(BEFORE ROW -> 堆删
-> AFTER ROW)。
"""


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS t040_trg")
            cur.execute("DROP TABLE IF EXISTS t040_log")
            cur.execute("CREATE TABLE t040_trg (id INT PRIMARY KEY, note VARCHAR(64))")
            cur.execute("CREATE TABLE t040_log (phase VARCHAR(16), id INT)")
            cur.execute("""CREATE TRIGGER t040_bd BEFORE DELETE ON t040_trg
                           FOR EACH ROW INSERT INTO t040_log VALUES ('bd', OLD.id)""")
            cur.execute("""CREATE TRIGGER t040_ad AFTER DELETE ON t040_trg
                           FOR EACH ROW INSERT INTO t040_log VALUES ('ad', OLD.id)""")
            cur.execute("""CREATE TRIGGER t040_bi BEFORE INSERT ON t040_trg
                           FOR EACH ROW SET NEW.note = CONCAT('ins-', NEW.id)""")
            cur.execute("INSERT INTO t040_trg VALUES (1, 'orig'), (2, 'orig')")

            # 冲突 REPLACE:先删旧行(触发 bd/ad)再插新行(触发 bi)
            cur.execute("REPLACE INTO t040_trg VALUES (1, 'replaced')")
            cur.execute("SELECT phase, id FROM t040_log ORDER BY id, phase")
            assert cur.fetchall() == ((b'ad', 1), (b'bd', 1)), \
                "REPLACE must fire BEFORE/AFTER DELETE triggers"

            # 无冲突 REPLACE:只触发 INSERT 触发器,不产生 DELETE 日志
            cur.execute("REPLACE INTO t040_trg VALUES (3, 'fresh')")
            cur.execute("SELECT phase, id FROM t040_log ORDER BY id, phase")
            assert cur.fetchall() == ((b'ad', 1), (b'bd', 1)), \
                "non-conflicting REPLACE must not fire DELETE triggers"

            cur.execute("SELECT id, note FROM t040_trg ORDER BY id")
            rows = cur.fetchall()
            assert rows == ((1, b'ins-1'), (2, b'orig'), (3, b'ins-3')), rows

            # 清理
            cur.execute("DROP TRIGGER t040_bi")
            cur.execute("DROP TRIGGER t040_bd")
            cur.execute("DROP TRIGGER t040_ad")
            cur.execute("DROP TABLE t040_trg")
            cur.execute("DROP TABLE t040_log")

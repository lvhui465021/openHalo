"""验证测试脚手架本身可用：MySQL 协议可连、可执行查询。"""


def run(cluster):
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            row = cur.fetchone()
            assert row == (1,), "expected (1,), got %r" % (row,)

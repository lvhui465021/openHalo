"""Minimal corpus compile-rate probe for CREATE PROCEDURE/FUNCTION."""
#!/usr/bin/env python3
"""MySQL 5.7 官方语料编译率探针(固化自 2026-09-05 会话的临时工具)。

用法:先用 halo_cluster 起一个测试集群,然后
  python3 compile_rate_probe.py <mysql_port> sp.test trigger.test sp_trans.test

对 sp.test/trigger.test/sp_trans.test 中每条 CREATE PROCEDURE/FUNCTION 语句
(含 mysqltest 定界符处理)原样发给 openHalo 的 MySQL 协议端口,PASS = 定义
被成功接受。统计口径与 2026-09-03 差距分析 §1/§2 一致:只统计定义语句本身
的成败,不受后续 CALL 级联影响;触发器定义依赖建表上下文,需在完整回放中
统计,本探针不覆盖。

已知:语料含少量非 UTF-8 字节(以 replace 解码);个别语句会让服务端段错误
(BUG#25411 的 /*!99999 门控注释体等,另归档),探针对断连自动重连续测。
"""
import sys
sys.path.insert(0, "/home/unvdb/pylibs")
import re, time, pymysql

def parse(path):
    raw = open(path, "rb").read().decode("utf-8", "replace")
    lines = raw.split("\n")
    skip_prefixes = ("#", "--", "if ", "if(", "while(", "}", "{", "connect ",
                     "let ", "disable", "enable", "source ", "echo", "eval",
                     "real_sleep", "sleep", "replace ", "remove_file",
                     "copy_file", "error ", "delimiter")
    stmts = []
    buf, capturing = [], False
    delim = ";"
    def endswith_delim(s):
        if len(s) >= len(delim) and s.endswith(delim):
            return delim
        return None
    for ln in lines:
        st = ln.strip()
        if capturing:
            buf.append(ln)
            d = endswith_delim(st)
            if d:
                text = "\n".join(buf)
                if text.endswith(d):
                    text = text[:-len(d)]
                stmts.append(text)
                buf, capturing = [], False
            continue
        if st.lower().startswith("delimiter"):
            tok = st.split(None, 1)[1] if len(st.split(None, 1)) > 1 else ";"
            delim = tok[:-1] if tok.endswith(";") else tok
            if len(delim) > 1 and delim[1] in "|$;":
                delim = delim[0]
            continue
        if not st or st.startswith(skip_prefixes):
            continue
        if re.match(r"(?i)^create\s+(or\s+replace\s+)?(procedure|function)\b", st):
            d = endswith_delim(st)
            if d:
                stmts.append(st[: len(st) - len(d)])
            else:
                capturing = True
                buf = [ln]
    return stmts

port = int(sys.argv[1])
files = sys.argv[2:]
conn = pymysql.connect(host="127.0.0.1", port=port, user="halo",
                       database="public", autocommit=True)
cur = conn.cursor()
import time as _t
_t.sleep(20)  # attach window
ok = fail = 0
fails = {}
for path in files:
    stmts = parse(path)
    fok = ffail = 0
    for sql in stmts:
        try:
            cur.execute(sql)
            cur.fetchall()
            ok += 1; fok += 1
        except pymysql.MySQLError as e:
            fail += 1; ffail += 1
            key = (e.args[0], (e.args[1] or "")[:55])
            fails[key] = fails.get(key, 0) + 1
            if e.args[0] in (0, 2006, 2013):
                # backend crashed: reconnect and continue with the next one
                try:
                    conn.close()
                except Exception:
                    pass
                time.sleep(2)
                conn = pymysql.connect(host="127.0.0.1", port=port, user="halo",
                                       database="public", autocommit=True)
                cur = conn.cursor()
        finally:
            for kind in ("PROCEDURE", "FUNCTION"):
                m = re.search(r"(?i)%s\s+[`]?(\w+)" % kind, sql)
                if m:
                    try: cur.execute("DROP %s IF EXISTS %s" % (kind, m.group(1)))
                    except Exception: pass
    print("%-14s stmts: %3d  ok: %3d  fail: %3d" %
          (path.split("/")[-1], fok + ffail, fok, ffail))

print("\nTOTAL: %d/%d = %.2f%%" % (ok, ok + fail, 100.0 * ok / (ok + fail)))
print("\nTop failure buckets:")
for (errno, msg), cnt in sorted(fails.items(), key=lambda x: -x[1])[:18]:
    print("  %4dx %s %s" % (cnt, errno, msg))

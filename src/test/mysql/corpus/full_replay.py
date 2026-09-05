#!/usr/bin/env python3
"""Full-statement corpus replay with per-kind CREATE statistics.

Executes every executable statement in the corpus (mysqltest meta lines
skipped) against openHalo's MySQL protocol, and reports per-kind compile
success for CREATE PROCEDURE / CREATE FUNCTION / CREATE TRIGGER.  Creates
the "test" schema up front because the corpus assumes it exists.
"""
import sys, re, time
sys.path.insert(0, "/home/unvdb/pylibs")
import pymysql
from pymysql.constants import FIELD_TYPE
_conv = pymysql.converters.decoders.copy()
_conv[FIELD_TYPE.DECIMAL] = lambda x: x
_conv[FIELD_TYPE.NEWDECIMAL] = lambda x: x

SKIP = ("#", "--", "if ", "if(", "while(", "}", "{", "connect ", "let ",
        "disable", "enable", "source ", "echo", "eval", "real_sleep",
        "sleep", "replace ", "remove_file", "copy_file", "error ",
        "delimiter", "exit", "skip", "query_vertical", "sorted_result",
        "send", "reap", "dec ", "inc ", "die", "assert")

def parse(path):
    raw = open(path, "rb").read().decode("utf-8", "replace")
    lines = raw.split("\n")
    SKIP = ("#", "--", "if ", "if(", "while(", "}", "{", "connect ",
            "connection", "let ",
            "disable", "enable", "source ", "echo", "eval", "real_sleep",
            "sleep", "replace ", "remove_file", "copy_file",
            "delimiter", "exit", "skip", "query_vertical", "sorted_result",
            "send", "reap", "dec ", "inc ", "die", "assert")
    stmts = []
    buf, capturing = [], False
    pending_error = False
    delim = ";"

    def endswith_delim(s):
        return delim if len(s) >= len(delim) and s.endswith(delim) else None

    for ln in lines:
        st = ln.strip()
        if capturing:
            buf.append(ln)
            d = endswith_delim(st)
            if d:
                text = "\n".join(buf)
                if text.endswith(d):
                    text = text[:-len(d)]
                stmts.append((text, pending_error))
                pending_error = False
                buf, capturing = [], False
            continue
        if st.lower().startswith("delimiter"):
            tok = st.split(None, 1)[1] if len(st.split(None, 1)) > 1 else ";"
            delim = tok[:-1] if tok.endswith(";") else tok
            if len(delim) > 1 and delim[1] in "|$;":
                delim = delim[0]
            continue
        if st.startswith("error ") or st.startswith("--error "):
            pending_error = True
            continue
        if not st or st.startswith(SKIP):
            continue
        if endswith_delim(st):
            stmts.append((st[: len(st) - len(delim)] if len(st) > len(delim) else st,
                          pending_error))
            pending_error = False
        else:
            capturing = True
            buf = [ln]
    return stmts

def classify(sql):
    if re.match(r"(?i)^\s*create\s+(or\s+replace\s+)?procedure\b", sql):
        return "PROC"
    if re.match(r"(?i)^\s*create\s+(or\s+replace\s+)?function\b", sql):
        return "FUNC"
    if re.match(r"(?i)^\s*create\s+(or\s+replace\s+)?(definer\s+\S+\s+)?trigger\b", sql):
        return "TRIG"
    return None

port = int(sys.argv[1])
files = sys.argv[2:]
conn = pymysql.connect(host="127.0.0.1", port=port, user="halo",
                       database="test", autocommit=True, use_unicode=False,
                       read_timeout=15, conv=_conv)
cur = conn.cursor()

stats = {k: [0, 0] for k in ("PROC", "FUNC", "TRIG")}   # ok, total
failures = []
allfail = {}

def reconnect():
    global conn, cur
    try:
        conn.close()
    except Exception:
        pass
    time.sleep(2)
    conn = pymysql.connect(host="127.0.0.1", port=port, user="halo",
                           database="test", autocommit=True, use_unicode=False,
                           read_timeout=15, conv=_conv)
    cur = conn.cursor()

for path in files:
    stmts = parse(path)
    print("== %s: %d statements" % (path.split("/")[-1], len(stmts)))
    # Reset context per file: the corpus assumes a clean "test" database and
    # the previous file's trailing "use" would otherwise leak.
    try:
        cur.execute("USE test")
    except Exception:
        reconnect()
    for sql, expect_err in stmts:
        kind = classify(sql)
        try:
            cur.execute(sql)
            while cur.nextset():
                try: cur.fetchall()
                except Exception: pass
            try: cur.fetchall()
            except Exception: pass
            if kind and not expect_err:
                stats[kind][0] += 1
        except pymysql.MySQLError as e:
            # An --error-marked statement that FAILED is a negative PASS,
            # but cleanup still runs so later same-name creations don't
            # cascade-fail.
            if expect_err:
                try:
                    cur.execute("ROLLBACK")
                except Exception:
                    reconnect()
            elif kind and e.args[0] in (1304, 1359):
                # A leftover same-name object from earlier corpus context:
                # drop it by name and retry once.
                name = re.search(r'"([\w]+)"', e.args[1] or "")
                if name:
                    drop = ("DROP TRIGGER IF EXISTS " if e.args[0] == 1359
                            else "DROP %s IF EXISTS " %
                            ("PROCEDURE" if kind == "PROC" else "FUNCTION"))
                    try:
                        cur.execute(drop + name.group(1))
                    except Exception:
                        try:
                            cur.execute("ROLLBACK")
                        except Exception:
                            reconnect()
                try:
                    cur.execute(sql)
                    while cur.nextset():
                        try: cur.fetchall()
                        except Exception: pass
                    stats[kind][0] += 1
                    continue
                except pymysql.MySQLError as e2:
                    e = e2
            elif kind:
                stats[kind][1] += 1
                failures.append((path.split("/")[-1], kind, e.args[0],
                                 (e.args[1] or "")[:60], sql[:90]))
                key = (e.args[0], (e.args[1] or "")[:55])
                allfail[key] = allfail.get(key, 0) + 1
            try:
                cur.execute("ROLLBACK")
            except Exception:
                pass
            if e.args[0] in (0, 2006, 2013):
                reconnect()
            elif "Lost connection" in str(e.args) or not conn.open:
                reconnect()

print("\n=== Per-kind CREATE success ===")
for k in ("PROC", "FUNC", "TRIG"):
    ok, tot = stats[k]
    tot = ok + tot
    print("%-5s %3d/%3d = %5.1f%%" % (k, ok, tot, 100.0 * ok / tot if tot else 0.0))

print("\n=== Failure buckets (all statements) ===")
for (errno, msg), cnt in sorted(allfail.items(), key=lambda x: -x[1])[:20]:
    print("  %4dx %s %s" % (cnt, errno, msg))

print("\n=== Per-kind failures ===")
for f in failures:
    print("  [%s|%s|%s] %s | %s" % f)

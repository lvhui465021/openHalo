#!/usr/bin/env python3
"""mysqltest .result 对齐与结果等价比对(骨架 v0)。

原理:mysqltest 的 .result 文件是"语句 echo(原样文本,含分隔符)+
结果块(tab 分隔)"的线性序列。回放器顺序执行语句序列,双指针对齐:
在 result 中顺序搜索每条语句的 echo(多行、空白归一),两个相邻锚点
之间的行即前一条语句的期望结果块;与实际结果行做归一化比较。

字段归一化:NULL 字面量、数值(Decimal 容差,容忍格式差异如 1.00 vs
1.0000)、其余字符串精确。行序:先逐行比较,失败再试"排序后集合等价"
(报告为 row_order_diff)。

输出统计:aligned(锚点对齐)、no_result(语句无期望输出块)、
match_exact / match_numeric / row_order_diff / mismatch / not_found,
不匹配样本 dump 到 <out>.mismatch.txt 供人工归桶。
"""
#!/usr/bin/env python3
"""mysqltest .result 对齐与结果等价比较器。

v0:语句 echo 双指针对齐 + 字段级 NULL/数值等价 + 行序回退比较。
v2(尾部):faithful mysqltest 分段语义——delimiter 为整参数(如
";//" 是三字符分隔符)、引号感知字符级扫描、convert_to_format_v1
回显归一,与 mysqltest read_command/do_delimiter 逐字对齐;sp.test
全语料 not_found=0 由此达成。

配套驱动:full_replay.py(执行引擎)。驱动需向 exec_fn 注入列头行
(mysqltest 期望块含表头)并自行剥离语句尾部分隔符。
"""
import re
import sys
sys.path.insert(0, "/home/unvdb/pylibs")

from decimal import Decimal, InvalidOperation

SKIP_PREFIXES = ("#", "if ", "if(", "while(", "}", "{", "connect ", "let ",
                 "disable", "enable", "source ", "echo", "eval", "real_sleep",
                 "sleep", "replace ", "remove_file", "copy_file",
                 "delimiter", "exit", "skip", "query_vertical", "sorted_result",
                 "send", "reap", "dec ", "inc ", "die", "assert")


def parse_test(path):
    """与 full_replay 相同的语句解析,额外返回每条语句的原样文本(含分隔符)
    供 result 锚点匹配。返回 [(text_with_delim, expect_error)]。"""
    raw = open(path, "rb").read().decode("utf-8", "replace")
    lines = raw.split("\n")
    stmts, buf, capturing = [], [], False
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
                full = "\n".join(buf)
                stmts.append((full, pending_error))
                pending_error = False
                buf, capturing = [], False
            continue
        if st.lower().startswith("delimiter"):
            tok = st.split(None, 1)[1] if len(st.split(None, 1)) > 1 else ";"
            delim = tok[:-1] if tok.endswith(";") else tok
            if len(delim) > 1 and delim[1] in "|$;":
                delim = delim[0]
            continue
        if st.startswith("--error ") or (
                st.startswith("error ")
                and (st[6:9].isdigit() or st[6:9].startswith("ER"))):
            pending_error = True
            continue
        if not st or st.startswith(SKIP_PREFIXES) or st.startswith("--"):
            continue
        if endswith_delim(st):
            stmts.append((ln.rstrip(), pending_error))
            pending_error = False
        else:
            capturing = True
            buf = [ln]
    return stmts


def norm_line(s):
    return s.strip()


def stmt_echo_lines(text):
    """语句在 result 中的 echo 行:原样多行,去首尾空行。"""
    return [l for l in text.split("\n")]


def field_equal(a, b):
    """字段级归一比较:NULL、数值(数值等价)、字符串精确。"""
    if a == b:
        return True
    if a == "NULL" and b in ("NULL", ""):
        return True
    if b == "NULL" and a in ("NULL", ""):
        return True
    try:
        da = Decimal(a)
        db = Decimal(b)
        # 数值等价:数值相等(1.00 == 1.0000);容差用于浮点表示差异
        if da == db:
            return True
        if da.is_finite() and db.is_finite():
            diff = abs(da - db)
            scale = max(abs(da), abs(db), 1)
            if diff <= scale * Decimal("1e-9"):
                return True
    except (InvalidOperation, ValueError, TypeError):
        pass
    return False


def block_equal(exp_lines, got_lines):
    """返回 (verdict, detail):exact / numeric / row_order_diff / mismatch。
    exp/got 均为行列表(tab 分隔字段)。"""
    if [l.rstrip("\t") for l in exp_lines] == [l.rstrip("\t") for l in got_lines]:
        return "match_exact", None
    # 字段级
    if len(exp_lines) == len(got_lines):
        all_ok = True
        for le, lg in zip(exp_lines, got_lines):
            fe = le.split("\t")
            fg = lg.split("\t")
            if len(fe) != len(fg) or not all(field_equal(a, b)
                                             for a, b in zip(fe, fg)):
                all_ok = False
                break
        if all_ok:
            return "match_numeric", None
    # 排序后集合等价
    if sorted(exp_lines) == sorted(got_lines):
        return "row_order_diff", None
    se = sorted("\t".join(sorted(f.split("\t"))) for f in exp_lines)
    sg = sorted("\t".join(sorted(f.split("\t"))) for f in got_lines)
    if se == sg:
        return "row_order_diff", None
    if len(exp_lines) == len(got_lines):
        ok = True
        for le, lg in zip(sorted(exp_lines), sorted(got_lines)):
            fe, fg = le.split("\t"), lg.split("\t")
            if len(fe) == len(fg) and all(field_equal(a, b)
                                          for a, b in zip(fe, fg)):
                continue
            ok = False
            break
        if ok:
            return "match_numeric", None
    return "mismatch", "exp=%r got=%r" % (exp_lines[:5], got_lines[:5])


def align_and_diff(stmts, exec_fn, result_path, expect_error_skip=True):
    """stmts: parse_test 输出。exec_fn(sql) -> (rows, error)。
    result_path: .result 文件。返回统计 dict 与 mismatch 样本列表。"""
    rlines = [norm_line(l) for l in open(result_path, encoding="utf-8", errors="replace")]
    # 预定位:顺序匹配每条语句的 echo 到 result 行序列(只对正向语句)
    anchors = []          # (stmt_idx, start_line, end_line_exclusive)
    pos = 0
    for idx, (text, expect_err) in enumerate(stmts):
        # --error statements DO set anchors (their echo+ERROR lines must not
        # pollute the previous statement's expected block); only the result
        # diff is skipped for them.
        echo = [norm_line(x) for x in stmt_echo_lines(text) if norm_line(x)]
        if not echo:
            anchors.append((idx, None, None))
            continue
        # 在 pos 起找 echo[0] 的行,然后逐行匹配(允许 result 中语句行后紧跟)
        found = None
        for i in range(pos, len(rlines)):
            if rlines[i] == echo[0]:
                k = i
                ok = True
                for e in echo[1:]:
                    k += 1
                    # 容忍 result 中多出来的空行
                    while k < len(rlines) and rlines[k] == "" and e != "":
                        k += 1
                    if k >= len(rlines) or rlines[k] != e:
                        ok = False
                        break
                if ok:
                    found = (i, k + 1)
                    break
        if found:
            anchors.append((idx, found[0], found[1]))
            pos = found[1]
        else:
            anchors.append((idx, None, None))

    stats = {"aligned": 0, "not_found": 0, "no_result": 0, "match_exact": 0,
             "match_numeric": 0, "row_order_diff": 0, "mismatch": 0,
             "skipped_error": 0}
    samples = []
    # 结果块 = 本锚点 end 到下一锚点 start(取下一个非 None start)
    next_start = [None] * len(anchors)
    last = None
    for i in range(len(anchors) - 1, -1, -1):
        next_start[i] = last
        if anchors[i][1] is not None:
            last = anchors[i][1]

    for idx, (text, expect_err) in enumerate(stmts):
        si, se = anchors[idx][1], anchors[idx][2]
        if expect_err and expect_error_skip:
            stats["skipped_error"] += 1
            continue
        if si is None:
            stats["not_found"] += 1
            continue
        stats["aligned"] += 1
        block_end = next_start[idx] if next_start[idx] is not None else len(rlines)
        exp_block = [l for l in rlines[se:block_end] if l != ""]
        rows, err = exec_fn(text)
        if err is not None:
            # 语料期望成功但我们失败:执行差异
            stats["mismatch"] += 1
            samples.append((idx, "exec_failed: %s" % err, text[:60],
                            exp_block[:5], []))
            continue
        got = ["\t".join("" if v is None else str(v) for v in r) for r in rows]
        if not exp_block and not got:
            stats["match_exact"] += 1
            continue
        if not exp_block:
            # 期望无输出但实际有:受影响行数等 mysqltest 不记录的内容
            stats["no_result"] += 1
            if got:
                samples.append((idx, "no_result (got output)", text[:60],
                                [], got[:5]))
            continue
        verdict, detail = block_equal(exp_block, got)
        stats[verdict] += 1
        if verdict in ("mismatch", "row_order_diff"):
            samples.append((idx, verdict + (": " + detail if detail else ""),
                            text[:60], exp_block[:5], got[:5]))
    return stats, samples


# ===================== v2: faithful mysqltest semantics =====================
META_WORDS = {"let", "eval", "echo", "connect", "source", "sleep", "real_sleep",
              "die", "skip", "send", "reap", "dec", "inc", "exit", "assert",
              "remove_file", "copy_file", "replace", "query_vertical",
              "sorted_result", "disable_warnings", "enable_warnings",
              "disable_result_log", "enable_result_log", "disable_query_log",
              "enable_query_log", "disable_abort_on_error", "character_set",
              "if", "while"}
COMMAND_METAS = {"remove_file", "file_exists", "sleep", "copy_file", "write_file",
                 "append_file", "mkdir", "rmdir", "connect", "disconnect",
                 "connection", "source", "perl", "send", "reap", "die", "exit",
                 "skip", "let", "dec", "inc", "eval"}


def v1_convert(q):
    """mysqltest convert_to_format_v1 逐字移植(5.7 默认 result-format-version=1):
    换行后跳过所有空白,除非前一个字符处于引号扫描。"""
    out = []
    i, n = 0, len(q)
    last_c_was_quote = False
    while i < n:
        c = q[i]
        if c == "\n" and not last_c_was_quote:
            out.append(c)
            i += 1
            while i < n and q[i].isspace():
                i += 1
            last_c_was_quote = False
        elif c in ("'", '"', "`"):
            out.append(c)
            i += 1
            while i < n and q[i] != c:
                out.append(q[i])
                i += 1
            if i < n:
                out.append(q[i])
                i += 1
            last_c_was_quote = True
        else:
            out.append(c)
            i += 1
            last_c_was_quote = False
    return "".join(out)


def parse_connect_args(arg):
    """connect (name,host,user,pass,db) → (name, user, db);root 映射为集群管理员
    halo(工具层对等翻译),*NO-ONE* → 无默认库。"""
    m = re.search(r"\((.*)\)", arg, re.S)
    if not m:
        return None
    parts = [p.strip() for p in m.group(1).split(",")]
    while len(parts) < 5:
        parts.append("")
    name, _host, user, _pass, db = parts[:5]
    user = "halo" if user in ("", "root") else user
    db = None if db in ("", "*NO-ONE*") else db
    return name, user, db


def parse_replace_pairs(text):
    """按引号感知切分 --replace_column/--replace_result 的参数 token。"""
    toks = []
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            break
        if text[i] in "'\"":
            q = text[i]
            i += 1
            j = i
            while j < n and text[j] != q:
                j += 1
            toks.append(text[i:j])
            i = j + 1
        else:
            j = i
            while j < n and not text[j].isspace():
                j += 1
            toks.append(text[i:j])
            i = j
    return toks


def parse_faithful(path):
    """按 mysqltest read_line()/do_delimiter() 语义分段。

    - '#'/'--'/空行 = 换行终结的 meta/注释,不进入语句;
    - 其余行做字符级、引号感知扫描,直到当前 delimiter(可跨行、可在行中);
    - 语句缓冲区先 convert_to_format_v1 再按首词分发:
      delimiter <arg>  → 换分隔符(arg 即 first_argument,旧分隔符已被扫描消费);
      error ...        → 下一条语句期待报错;
      META_WORDS 首词  → meta 跳过;
      其它             → 查询语句(sql 为 v1 归一化文本,分隔符已消费)。
    返回事件列表:{"kind": "query"|"echo"|"meta", ...}"""
    raw = open(path, "rb").read().decode("utf-8", "replace")
    s = raw
    n = len(s)
    i, line = 0, 1
    delim = ";"
    expect_err = False
    events = []
    conn = "default"
    skip_until_enable = False

    def bump_line(ch):
        nonlocal line
        if ch == "\n":
            line += 1

    while i < n:
        if skip_until_enable:
            k = s.find("--enable_parsing", i)
            if k < 0:
                break
            line += s.count("\n", i, k)
            i = k
            skip_until_enable = False
            continue
        # 语句起点(R_LINE_START):跳过空白
        while i < n and s[i].isspace():
            bump_line(s[i])
            i += 1
        if i >= n:
            break
        c = s[i]
        if c == "#":                      # 换行终结注释
            while i < n and s[i] != "\n":
                i += 1
            continue
        if c == "-" and i + 1 < n and s[i + 1] == "-":   # --meta / -- 注释
            j = i
            while j < n and s[j] != "\n":
                j += 1
            body = s[i + 2:j].strip()
            bl = body.lower()
            if bl == "error" or bl.startswith("error "):
                expect_err = True
            elif bl == "echo" or bl.startswith("echo "):
                events.append({"kind": "echo", "out": body[4:].strip(),
                               "line": line, "conn": conn})
            elif bl.startswith("disable_parsing"):
                skip_until_enable = True
            elif bl.startswith("enable_parsing"):
                pass
            elif bl.startswith("replace_column"):
                events.append({"kind": "replace_column",
                               "pairs": parse_replace_pairs(body[14:]),
                               "line": line})
            elif bl.startswith("replace_result"):
                events.append({"kind": "replace_result",
                               "pairs": parse_replace_pairs(body[14:]),
                               "line": line})
            elif bl.startswith("replace_regex"):
                events.append({"kind": "replace_regex",
                               "pairs": parse_replace_pairs(body[13:]),
                               "line": line})
            elif bl.startswith("connect"):
                pc = parse_connect_args(body[7:])
                if pc:
                    events.append({"kind": "connect", "name": pc[0],
                                   "user": pc[1], "db": pc[2], "line": line})
                    conn = pc[0]
            elif bl.startswith("disconnect"):
                events.append({"kind": "disconnect",
                               "name": body[10:].strip(), "line": line})
            elif bl.startswith("connection"):
                conn = body[10:].strip()
                events.append({"kind": "connection", "name": conn, "line": line})
            if expect_err and bl.split(None, 1)[0] in COMMAND_METAS:
                # mysqltest 里 --error 的期望由下一条"命令"消费;文件操作类
                # 命令(如 --remove_file,配合 --error 0,1 使用)也消费它。
                expect_err = False
            i = j
            continue
        if c == "}":                      # '}' 需独立成行才终结,单独跳过
            while i < n and s[i] != "\n":
                i += 1
            continue
        # delimiter 终结的语句扫描(引号感知)
        start_line = line
        out = []
        in_q, slash = None, False
        used_delim = ""
        while i < n:
            ch = s[i]
            if ch == "\n":
                bump_line(ch)
                out.append(ch)
                i += 1
                slash = False
                continue
            if in_q:
                out.append(ch)
                i += 1
                if slash:
                    slash = False
                elif ch == "\\" and in_q != "`":
                    slash = True
                elif ch == in_q:
                    in_q = None
                continue
            if delim and s.startswith(delim, i):
                i += len(delim)
                used_delim = delim
                break
            if ch in "'\"`":
                in_q = ch
            out.append(ch)
            i += 1
        v1 = v1_convert("".join(out))
        v1l = v1.lstrip()          # read_command: 跳过整条命令的前导空白
        text = v1l.strip()
        if not text:
            continue
        m = re.match(r"(\S+)\s*", text, re.S)
        word = m.group(1).lower()
        rest = text[m.end():].strip()
        if word == "delimiter":
            if rest:
                delim = rest
            continue
        if word == "error":
            expect_err = True
            continue
        if word in ("connect", "disconnect", "connection"):
            if word == "connect":
                pc = parse_connect_args(rest)
                if pc:
                    events.append({"kind": "connect", "name": pc[0],
                                   "user": pc[1], "db": pc[2], "line": start_line})
                    conn = pc[0]
            elif word == "disconnect":
                events.append({"kind": "disconnect", "name": rest.strip(),
                               "line": start_line})
            else:
                events.append({"kind": "connection", "name": rest.strip(),
                               "line": start_line})
                conn = rest.strip()
            continue
        if word in META_WORDS:
            events.append({"kind": "meta", "word": word, "line": start_line})
            continue
        # echo = 归一化缓冲区(保留分隔符前的尾随空格/换行)+ 分隔符
        events.append({"kind": "query", "sql": text, "v1echo": v1l + used_delim,
                       "expect_err": expect_err, "line": start_line,
                       "conn": conn})
        expect_err = False
    return events


# ================================================================= anchors


def compute_anchors(stmts, rlines):
    """逐字复制 RD.align_and_diff phase-1(骨架 v0.1:--error 语句也设锚点,
    其 echo+ERROR 行被消费,不再污染前一条语句的期望块)。"""
    anchors = []
    pos = 0
    for idx, (text, expect_err) in enumerate(stmts):
        echo = [norm_line(x) for x in stmt_echo_lines(text) if norm_line(x)]
        if not echo:
            anchors.append(None)
            continue
        found = None
        for i in range(pos, len(rlines)):
            if rlines[i] == echo[0]:
                k = i
                ok = True
                for e in echo[1:]:
                    k += 1
                    while k < len(rlines) and rlines[k] == "" and e != "":
                        k += 1
                    if k >= len(rlines) or rlines[k] != e:
                        ok = False
                        break
                if ok:
                    found = (i, k + 1)
                    break
        anchors.append(found)
        if found:
            pos = found[1]
    return anchors


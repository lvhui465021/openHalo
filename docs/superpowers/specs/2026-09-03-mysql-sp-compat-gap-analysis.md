# MySQL 5.7 存储过程兼容性 — 回归测试评测与研发方案

**日期**：2026-09-03
**评测对象**：openHalo（`feature/mysql-stored-procedure-m1` 分支，含 M1–M8）
**测试语料**：MySQL 5.7 官方回归用例 `/home/unvdb/mysql-server-5.7/mysql-test/t/` 中的
`sp.test`、`trigger.test`、`sp_trans.test`

---

## 1. 方法

MySQL 的 `.test` 文件是 mysqltest 脚本（含 `delimiter`、`--error`、`eval`、`connect` 等指令），
不能直接喂给客户端。为此写了一个解析器（`mysqltest_parse.py`）：跟踪 `delimiter` 变化、
剥离注释与指令行、捕获每条语句前的 `--error ER_XXX`（用 `errmsg-utf8.txt` 还原成 errno），
跳过依赖 `$var`/`eval`/`connect` 的少量语句（三份文件合计仅约 60 行）。

再用一个执行器（`run_sp_compat.py`）把解析出的语句**按顺序**打到 openHalo 的 MySQL 协议
（pymysql），逐条分类：

| 判定 | 含义 |
|---|---|
| `OK` | MySQL 期望成功，openHalo 成功 |
| `FAIL` | MySQL 期望成功，openHalo 报错 |
| `OK_NEG` | MySQL 期望某错误码，openHalo 报了同一码 |
| `WRONG_ERR` | MySQL 期望错误码 X，openHalo 报了别的码 |
| `MISSING_ERR` | MySQL 期望报错，openHalo 却接受了（过于宽松） |

**工程细节**（保证测量不失真）：
- CALL 返回结果集会打乱 pymysql 协议帧（见 §4.1），因此 `CALL`/`DO`/`EXECUTE` 走一次性
  连接，其协议错乱不污染主会话。
- 服务端设 `statement_timeout=8s`，避免慢/死循环过程把客户端连接拖成僵死 socket。
- 连接丢失（errno 0/2006/2013…）或帧错乱时重建连接（带重试）后继续。

**统计口径**：`create_procedure/function/trigger` 的“编译通过率”只统计**定义语句自身**的
成败，不受后续 `CALL` 级联失败影响，是最干净的能力信号。负向（`--error`）用例里有一部分
`WRONG_ERR` 是级联噪声（定义没建成 → `CALL` 报 1305/1105 而非期望的语义错误），已在分析中
单独剔除。

---

## 2. 兼容性总分

执行语句总数：**4553**（sp.test 2897 + trigger.test 1384 + sp_trans.test 272）。

### 例程/触发器定义编译通过率（三份用例合计）

| 定义类型 | 通过 | 总数 | 通过率 |
|---|---|---|---|
| `CREATE PROCEDURE` | 204 | 358 | **57%** |
| `CREATE FUNCTION` | 104 | 146 | **71%** |
| `CREATE TRIGGER` | 137 | 149 | **92%** |

### 负向（`--error`）错误码对齐（三份合计 217 条）

| 判定 | 数量 | 占比 |
|---|---|---|
| `OK_NEG`（错误码正确） | 40 | 18% |
| `WRONG_ERR`（错误码不符） | 129（其中约 27 为级联噪声，约 102 为真实不符） | — |
| `MISSING_ERR`（openHalo 过于宽松） | 48 | 22% |

**读法**：触发器编译已很成熟（92%，验证 M7 站得住）；存储过程/函数的定义编译还有明显缺口，
且**绝大多数缺口集中在极少数几个根因上**（见 §3）。负向路径上，超过一半 `WRONG_ERR` 其实是
“语义错误退化成 1064 语法错误”——即定义根本没解析过，因此修好编译缺口会连带修复大量
错误码不符。

---

## 3. 缺口清单（按影响排序）

### A. 编译期语法缺口（正向，影响最大）

| # | 缺口 | 失败数 | 根因 | 修复方案 |
|---|---|---|---|---|
| **A1** | **单语句过程体（无 `BEGIN…END`）** | **112** | `mysql_routine_body` 产生式硬性以 `BEGIN_P` 开头（[mys_gram.y:11881](src/backend/parser/mysql/mys_gram.y:11881)）；只有函数的单语句 `RETURN expr` 走了特例。`create procedure p() insert into …`、`… call …`、`… set …` 等一律 1064 语法错误 | 让例程体捕获在遇到非 `BEGIN` 的首 token 时，捕获**单条语句**作为体，内部按 `BEGIN <stmt>; END` 交给 plmysql（与已有的 `RETURN expr` 特例同构，扩展到任意单语句）。触发器体已支持单语句（[mys_gram.y:8803](src/backend/parser/mysql/mys_gram.y:8803)），可复用该思路 |
| **A2** | **`DETERMINISTIC` 等特性用在 `PROCEDURE` 上** | **20** | MySQL 特性 `DETERMINISTIC`→plpgsql `volatility=stable` 的 DefElem，被原样塞进 `is_procedure=true` 的 `CreateFunctionStmt`；PG 的 CREATE PROCEDURE 不接受 volatility 属性 → “invalid attribute in procedure definition”(1105)。样例全部形如 `create procedure p() deterministic begin …` | 建过程时（`is_procedure`）过滤掉由 MySQL 特性派生的 `volatility`/`leakproof`/`strict`/`cost`/`rows` DefElem（`DETERMINISTIC` 对过程是纯咨询性），或把它降级为 `plmysql.deterministic` 元数据 GUC，不传给 PG 内核 |
| **A3** | **例程体表达式里的双引号字符串 `"…"`** | 4 | 体内表达式（如 `CONCAT(arg, "")`、`RETURN ""`）交给标准 PG 解析器校验，`"…"` 被当成分隔标识符 → “zero-length delimited identifier”。默认 sql_mode（无 ANSI_QUOTES）下 MySQL 视其为字符串 | plmysql 体内表达式解析需按 MySQL 字符串语义处理 `"…"`（与本分支已给主扫描器 `mys_scan.l` 加的 ANSI_QUOTES/`<xd>` 逻辑对齐）。plmysql 走的是独立扫描/SPI 路径，需要单独接入 sql_mode 位 |
| **A4** | **例程体内 `SET @@sysvar` / `SET sql_mode=…`** | 4 | 体内 `SET SQL_MODE='TRADITIONAL'` 被 plmysql 当成对未声明局部变量赋值 → “is not a known variable”(1064) | plmysql 的 `SET` 语句需区分：赋值本地变量 vs 设置系统/会话变量（透传给适配器的 `MysVariableSetStmt`）。这是设计文档 §7 风险 2 “SET 语句歧义”遗留的一半 |

> A1+A2 合计 132 条，占存储过程编译失败的绝大部分。仅修 A1，`CREATE PROCEDURE` 通过率
> 预估从 57% → ~88%；再修 A2 → ~94%。

### B. 类型系统缺口

| # | 缺口 | 失败数 | 说明 | 方案 |
|---|---|---|---|---|
| **B1** | **`ENUM(...)` / `SET(...)` 作为 `DECLARE` 变量类型或 `RETURNS` 类型** | 6 | `declare v enum('a','b')` / `returns enum(...)` → “type does not exist”(1091)。openHalo 无 ENUM/SET 类型域 | 中大型：需要在 aux_mysql 里提供 ENUM/SET 语义（或退化为受 CHECK 约束的文本域），并让例程/函数参数与返回类型解析支持内联 `enum(...)`/`set(...)` |
| **B2** | **列级 `CHAR … BINARY` / `CHARSET x` 特性** | 3 | `returns char binary` / `returns char(10) charset koi8r` → 1064。MySQL 期望的是 1235(NOT_SUPPORTED) 而非语法错误 | 语法层接受并忽略（或映射）`BINARY`/`CHARSET` 类型特性；至少给出 1235 而非 1064 |

### C. 运行期 / 协议缺口（不在编译通过率里，但直接影响可用性）

| # | 缺口 | 证据 | 方案 |
|---|---|---|---|
| **C1** | **`CALL` 多结果集协议帧错乱** | **已用官方 `mysql` CLI 复核，确认是服务端真实缺陷，与 pymysql 无关**：`CALL proc()`（体内一条裸 `SELECT`，返回一个结果集）后面若还有下一条语句（无论是另一个 `CALL` 还是普通 `SELECT`，且无论是否属于同一个 multi-statement 批次），下一条语句的数据要么整体丢失、要么连接直接报 “Lost connection”/pymysql 的 “Packet sequence number wrong”；只作为连接里唯一一条语句时完全正常。定位到一个真实、已修的子缺陷：`plmysql_push_execsql_resultset()`（`pl_exec_ext.c`）每次推送本例程自己的结果集时都会重算共享全局 `moreResultsFlag`，用完本例程自己的计数后无条件清零——但这个全局同时被顶层 multi-statement 循环（`tcop/postgres.c`）用来表示“这批里还有没执行的语句”，清零会把顶层循环刚设好的“还有更多语句”信号覆盖掉。**已修**（`estate->outer_more_results_flag` 快照 + 兜底，而非硬编 0）。但这**不是** C1 的全部根因：修复后用 pymysql 显式开 `CLIENT_MULTI_STATEMENTS` 复测，`CALL` 自身结果集仍正确，可后续语句的数据依然拿不到（`cur.nextset()` 返回 True 但 `fetchall()` 为空），只是连接不再整体失联。且经排查发现 `mysql` CLI 对分号分隔的多条语句实际是**逐条独立发送/独立收发**（不是一次性 multi-statement 包），`tcop/postgres.c` 里 `stmtIndex</stmtsNum` 那段判断因此在这个路径下从未真正触发过（`stmtsNum` 恒为 1）——说明还有另一层问题（很可能是 `CALL` 自身收尾包和/或包序号计数器在跨语句之间没有正确处理），未定位到具体代码位置 | 已完成部分：`outer_more_results_flag` 快照修复（`pl_exec.c`/`pl_exec_ext.c`/`plmysql.h`），回归见 `test_028`。剩余部分需要专门的协议抓包/单步调试（推荐用 `tcpdump`/`Wireshark` 解 MySQL 协议帧，或在 `adapter.c` 的发包函数上打点比对包序号），定位跨语句的包序号/收尾包缺陷，工作量与原方案的“2–4 天”估计相近，且现在有了更精确的复现步骤和范围 |
| **C2** | **过程内 `COMMIT`/`ROLLBACK` 运行期 1105** | **根因已重新定位（2026-09-04 复测更正）**：MySQL 协议的 CALL 分发其实已经正确构造了 `atomic=false` 的 `CallContext`（`mys_utility.c`/`utility.c` 的 `T_CallStmt` 分支与标准 PG 路径一致，实测 `isAtomicContext=0`）。真正原因是 `ExecuteCallStmt()`（`functioncmds.c`）里一条更早、更宽的 PG 原生规则：只要目标过程的 `pg_proc.proconfig` 非空就无条件把 `atomic` 强制改回 `true`（注释：GUC 栈在事务边界弹不出去）。而 plmysql **每一个**例程都会把 `sql_mode`/`created`/`last_altered`/`definer` 等元数据以 `SET`-style DefElem 写进 `proconfig`（见 `mys_make_routine_meta_item`），所以这条限制对所有 MySQL 例程恒为真——与 SQL SECURITY DEFINER/INVOKER 无关（两种都试过，一样报错）。即 M9 之前设计文档 §7 风险 6 的描述已过时，实际是元数据存储机制与 PG 事务控制语句的结构性冲突，不是简单的“少传一个标志位” | 三选一，均有代价：**(a)** 把这些元数据挪出 `proconfig`（例如专用 catalog 表或 `COMMENT ON FUNCTION`），恢复 `proconfig` 为空——改动面大，牵涉 SHOW CREATE PROCEDURE/information_schema.ROUTINES/mysqldump 导出等已完成里程碑（test_012/016/019 都依赖当前存储方式），需要专项评审；**(b)** 仅对“确实含有 COMMIT/ROLLBACK”的例程尝试绕过该限制（例如探测请求时临时清空/搬移 proconfig）——本质是绕开 PG 官方为 GUC 栈安全设的保护，风险高，不建议；**(c)** 维持现状，作为已知限制记录（MySQL 例程可以合法使用显式事务控制，但目前会报 1105）。建议与用户确认取舍后再排期，不要在未评审下直接改 |

### D. 错误码与严格性缺口（负向，`MISSING_ERR`=openHalo 过于宽松）

按 MySQL 期望错误码归并（三份合计 48 条）：

| 期望错误码 | 次数 | 语义 | openHalo 现状 |
|---|---|---|---|
| `ER_TABLE_NOT_LOCKED` (1100/1099) | 8 | `LOCK TABLES` 后访问未锁表 | 不强制 LOCK TABLES 语义 |
| `ER_WRONG_SPVAR_TYPE_IN_LIMIT` (1691) | 6 | `LIMIT` 处用了错误类型的 SP 变量 | 不校验 |
| `ER_CANT_UPDATE_USED_TABLE_IN_SF_OR_TRG` (1442) | 3 | 触发器/函数修改正被触发语句使用的表 | 不强制 |
| `ER_SP_NO_RECURSION` (1424) | 3 | 经 `SELECT`/视图的间接函数递归 | 现有守卫只拦直接重入 |
| `ER_BAD_FIELD_ERROR`/`ER_CANT_REOPEN_TABLE` (1054/1137) | 6 | 字段/表复用检查 | 部分退化为 1064 |
| `ER_COMMIT_NOT_ALLOWED_IN_SF_OR_TRG` (1422) | 4 | 函数/触发器内隐式提交（DDL 等），非字面 COMMIT | 本分支只拦了字面 `COMMIT`/`ROLLBACK`，未覆盖隐式提交语句 |
| 触发器专属：`ER_SP_NO_RETSET`(1415)、`ER_STMT_NOT_ALLOWED_IN_SF_OR_TRG`(1336)、`ER_SP_BADRETURN`(1313)、`ER_TRG_ON_VIEW_OR_TEMP_TABLE`(1361)、`ER_TRG_IN_WRONG_SCHEMA`(1435)、`ER_NO_TRIGGERS_ON_SYSTEM_SCHEMA`(1465) | 各 1–2 | 触发器体内的语句/返回/对象限制 | 未强制 |
| `ER_SP_UNDECLARED_VAR`(1327)、`ER_UNKNOWN_SYSTEM_VARIABLE`(1193) | 2 | 引用未声明变量 / 未知 `@@sysvar` | 编译期未拒绝 |

> 这些是“宽松”而非“错误结果”，危害次于 A/B/C，但影响与 MySQL 客户端/ORM 的报错契约。

---

## 4. 研发路线图（建议分期与工作量）

以“投入产出比”排序：

### M9 — 编译期语法收尾（**首选，收益最大，风险低**）✅ 已完成（2026-09-04）
- **A1 单语句过程体**：例程体捕获支持非 `BEGIN` 首 token 的单语句。
- **A2 过程特性属性过滤**：`is_procedure` 时剔除 volatility 类 DefElem。
- **A3 体内双引号字符串**：根因不是 sql_mode 接入不到位，而是 plmysql 自己的词法层
  （`pl_scanner.c`）从未使用过 MySQL 风格的核心扫描器（`mys_core_yylex`/`mys_scan.l`），
  一直在用 PG 原生的 `core_yylex`/`scan.l`——例程体内的任何字面量都按 PG 词法规则而非
  MySQL 规则解析。改用 `mys_core_yylex` 后顺带暴露了 `pl_gram.y` 与 `mys_gram.y` 的“核心
  token”声明顺序早已不同步（`MysqlUserVariableName`/`MysSysVarName` 插入在 mys_gram.y 里、
  未同步进 pl_gram.y），导致 `ICONST` 及之后所有 token 编号错位——一并修正。
- **A4 体内 `SET` 系统变量消歧**：复用 `isSystemVariable()`（与顶层 SET 语句同一套注册表）
  区分“系统变量”与“未声明局部变量”。
- 回归：`src/test/mysql/t/test_024`–`test_027`（单语句体、DETERMINISTIC、词法修复、SET 系统
  变量消歧）。
- 实测（`sp.test`，最大受益文件）：`create_procedure` 编译通过率 57%→79%（三文件合计
  57%→76%，204/358→272/358）；`create_function`/`create_trigger` 持平，无回归。

### M10 — 运行期/协议正确性（**用户可感知的高优先级**）
- **C1 CALL 多结果集帧错乱**（~2–4 天，需先复核）：这是任何用 CALL + 结果集的真实客户端都会
  撞到的问题，优先级应高。
- **C2 CALL 非原子执行 + 事务语句**：**根因已重新定位**（见 §3 表格更新）——不是缺一个
  `atomic=false` 标志位，而是 plmysql 例程元数据的存储方式（`pg_proc.proconfig`）与 PG 原生
  对“含 proconfig 的过程恒强制 atomic=true”的保护规则结构性冲突。修复需要挪动元数据存储位置，
  改动面覆盖 test_012/016/019 已验证的 dump/metadata 路径，建议单独立项评审，不纳入本轮
  快速修复范围。

### M11 — 类型系统
- **B2 `BINARY`/`CHARSET` 类型特性**（~1 天，接受并忽略或给 1235）。
- **B1 ENUM/SET 类型**（~1–2 周，独立特性）：投入大，建议独立立项，非 SP 专属。

### M12 — 严格性/错误码对齐（打磨）
- 编译期：**A/D 修好后**补 1327（未声明变量）、1193（未知 `@@sysvar`）、1691（LIMIT 变量类型）
  的编译期检查（~2–3 天）。
- 触发器语义：1415/1336/1313/1442/1361/1435/1465（~3–5 天，逐条按 MySQL 手册加 guard）。
- LOCK TABLES 语义（1100/1099）、间接递归（1424）：投入较大、优先级低，可延后。

---

## 5. 测量局限与后续

- **未覆盖**：`sp.test` 中依赖 `eval`/`connect`/多连接的极少量用例；`sp-security`/`sp-error`
  等未纳入（可作为下一轮）。ENUM/字符集相关失败中，一部分是 openHalo 缺少对应类型域而非 SP
  引擎问题。
- **`WRONG_ERR` 需分层看**：约 102 条“真实不符”里，很大比例是“语义错误退化成 1064”，会随
  M9 的编译修复自动改善，不应单独计入 SP 引擎缺陷。
- **C1（CALL 帧错乱）已用官方 `mysql` CLI 复核，非客户端实现差异**：定位并修复了其中一个真实
  子缺陷（`moreResultsFlag` 被结果集推送逻辑无条件清零，见 §3 表格更新），但完整问题仍未解决，
  详情与复现步骤见 §3 C1 行。
- 复现实验脚本与逐条结果 JSON 保存在会话 scratchpad：`mysqltest_parse.py` /
  `run_sp_compat.py` / `analyze.py` / `*.result.json`；可固化进 `src/test/mysql/` 作为持续
  兼容性看板。

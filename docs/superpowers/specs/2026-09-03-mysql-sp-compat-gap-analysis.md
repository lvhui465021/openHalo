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
| **B2** | **列级 `CHAR … BINARY` / `CHARSET x` 特性** | 3 | **已修（2026-09-04），且发现比报告原描述更严重**：`returns char(10) charset koi8r` 确实只是 1064；但 `returns char(10) binary`（裸 `BINARY`，前面没有 `CHARACTER SET`/`CHARSET`）不是语法错误而是**服务端直接段错误（SIGSEGV）崩溃**，日志里能看到 `terminated by signal 11` 且连带踢掉同实例上所有其他会话——`mys_gram.y` 的 `opt_charset_with_opt_binary` 产生式当年只写了“先 CHARSET 后可选 BINARY”一种顺序，裸 `BINARY`/`BINARY` 在前的两种写法整段被注释掉，导致这个 token 在 `RETURNS` 位置被留在一个语法没准备好接收的地方 | 已修：把注释掉的 `\| BINARY` 与 `\| BINARY character_set charset_name` 两个分支补全（语法层接受并忽略，和已有的 charset-first 分支一致），bison 冲突数不变（仍是 `%expect 48`）。四种顺序（纯 `BINARY`、`CHARSET x`、`CHARSET x BINARY`、`BINARY CHARSET x`）均已验证不再崩溃、能正确编译执行。回归见 `test_029` |

### C. 运行期 / 协议缺口（不在编译通过率里，但直接影响可用性）

| # | 缺口 | 证据 | 方案 |
|---|---|---|---|
| **C1** | **`CALL` 多结果集协议帧错乱** | **已彻底定位并修复（2026-09-04）**，已用官方 `mysql` CLI 与 pymysql（含显式 `CLIENT_MULTI_STATEMENTS`）双重复核。真根因：MySQL 协议下 `CALL` 的响应结构上恒为“例程自身结果集 + 一个额外的收尾 OK 包”（`adapter.c` 的 `endCommand()` 对 `CMDTAG_CALL` 恒调用 `sendOKPacket()`，不管例程体是否有裸 `SELECT`），这两部分共享同一个 `moreResultsFlag` 全局。`plmysql_push_execsql_resultset()`（`pl_exec_ext.c`）之前把“本例程自己的结果集数是否推完”当成了整个 `CALL` 的终点，用完就把标志清零/回退——但那不是终点，后面恒定还有一个收尾 OK 包。客户端看到结果集自身的 EOF 说“没有更多了”，便提前认定整个 `CALL` 已结束，而服务端随后又发出那个客户端没打算再读的收尾包，正好卡在“连接以为已空闲、其实还有未读字节”的位置，砸坏了同一连接上后续任何语句的读取（无论是另一个 `CALL` 还是普通 `SELECT`，也无论是一次性 multi-statement 包还是逐条独立收发）——这正是 pymysql 报 “Packet sequence number wrong”、`mysql` CLI 报 “Lost connection” 或后续语句数据整体丢失的原因 | **已修**：结果集自身完成包的标志恒置“还有更多”（`HALO_SVR_MORE_RESULTS_EXISTS`，因为收尾 OK 包恒定紧随其后），只有在推完本例程自己的全部结果集**之后**才把标志还原为 `outer_more_results_flag`（顶层调度循环快照下来的真实“是否还有更多顶层语句”），留给那个稍后发送的收尾 OK 包携带。单结果集/多结果集、独占连接/后跟其他语句、一次性 multi-statement 包/逐条独立收发均已验证。回归见 `test_028`（`src/test/mysql`） |
| **C2** | **过程内 `COMMIT`/`ROLLBACK` 运行期 1105** | **已定位并部分修复（2026-09-04）**。根因是 `ExecuteCallStmt()`（`functioncmds.c`）里两条各自独立、任一条都会把 `atomic` 强制改回 `true` 的 PG 原生规则：**规则1** 只要目标过程的 `pg_proc.proconfig` 非空（GUC 栈在事务边界弹不出去）；**规则2** 只要 `prosecdef=true`（SECURITY DEFINER，`StartTransaction()` 要求安全上下文栈必须为空）。MySQL 协议的 CALL 分发本身没问题（`isAtomicContext` 计算和传递都正确）。**规则1 已修复**：plmysql 例程元数据（definer/sql_mode/created/last_altered/sql_data_access）已从 `pg_proc.proconfig` 迁移到一个专用的 `plmysql` security label（`mys_plmysql_meta_marker()`/`mys_plmysql_set_meta_label()`，`mys_utility.c`；仍随 `pg_dump`/`pg_restore` 走，作为 `SECURITY LABEL FOR plmysql ON FUNCTION/PROCEDURE ...` 语句；MySQL 触发器的私有底层函数保持用 proconfig 不变，因为触发器从不走 CALL 的 atomic/non-atomic 判定，本来就不受这条规则影响）；`mysql.get_plmysql_config()`（aux_mysql 1.11）优先读 label，找不到再退回 proconfig，兼容触发器和升级前的旧对象。**规则2 未修复，且不是同一类问题**：MySQL 5.7 不写 `SQL SECURITY` 子句时默认 DEFINER，`mys_apply_default_sql_security()` 据此把 `prosecdef` 默认置 `true`——而真实 MySQL 的 DEFINER 只是权限检查身份、并没有 PG 这种"安全上下文栈"概念，所以这是 PG 与 MySQL 之间一条独立的、更深的语义鸿沟，不因为修好规则1 就消失。**实测结果**：显式 `SQL SECURITY INVOKER` 的例程内 COMMIT/ROLLBACK 现在完全可用（修复前无论 DEFINER/INVOKER 都报错，已用两种模式验证过）；不写 `SQL SECURITY`（MySQL 默认，即 DEFINER）的例程仍报 1105——`test_030` 把这个已知限制显式钉住（断言必须仍是 1105，而非静默假设通过），一旦规则2 被修复会在测试里被发现，不会悄悄过期 | 规则1：已完成，见 `mys_utility.c`/`pl_handler.c`/`aux_mysql--1.10--1.11.sql`，回归见 `test_030`。规则2 需要与用户确认取舍：**(a)** 维持现状（DEFINER 默认 + 已知限制），文档记录；**(b)** 重新设计 DEFINER 语义，不依赖 PG 原生 `prosecdef`/安全上下文栈机制，而是仿照本次 sql_mode 的做法在 `plmysql_call_handler` 里手动切换/恢复有效用户——但这就是本 session 早前已经明确搁置的"DEFINER 用户到 pg_proc 属主映射"那个更大的权限模型话题，工作量和风险都不小；**(c)** 权衡下把 MySQL 例程默认 SQL SECURITY 改回 INVOKER（放弃对默认 DEFINER 语义的精确匹配，换取事务控制默认可用）——会直接影响 `test_023`（本 session 早前实现并测试过的默认值行为），需要重新评估这个取舍是否值得 |

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
| `ER_TRG_ON_VIEW_OR_TEMP_TABLE`(1361)、`ER_NO_TRIGGERS_ON_SYSTEM_SCHEMA`(1465) | 各 1–2 | 触发器建在 VIEW/临时表/MySQL 系统 schema 上 | ✅ 已完成（2026-09-04）：VIEW 情形本来就会被 PG 原生 `CreateTrigger()` 拒绝（无存储、没法挂行级触发器），只是错误码通用（1105）；临时表和系统 schema 情形之前完全没拦（PG 原生对两者都无此限制）。`mys_check_mysql_trigger_target()` 在原生路径前统一按 MySQL 错误码/文案拦三种情形，回归见 `test_032` |
| `ER_SP_NO_RETSET`(1415)、`ER_STMT_NOT_ALLOWED_IN_SF_OR_TRG`(1336) | 各 1–2 | 触发器返回结果集 / 函数或触发器内动态 SQL | ✅ **复测更正（2026-09-04）：其实早就实现了**（`pl_exec.c`/`pl_gram.y`，分别在语句执行/编译期检查），报告原先写"未强制"是因为最初复测方法有误——只测了 `CREATE TRIGGER` 编译通过，没有真正 `INSERT` 触发执行去触发运行期检查。用真实触发执行复核后确认两者都按 MySQL 错误码正确拒绝，不需要改代码 |
| `ER_SP_BADRETURN`(1313)、`ER_TRG_IN_WRONG_SCHEMA`(1435) | 各 1–2 | RETURN 语义 / 触发器与表 schema 不一致 | 未强制。1313 复测发现比预想复杂：真实 MySQL 里 `RETURN` 语义本身按 FUNCTION/PROCEDURE/TRIGGER 三种上下文分别限制（不只是"有没有返回值"），要对齐需要先核实清楚三种上下文各自的真实行为，不是单纯错误码替换；1435 需要先确认 MySQL 语法是否真的允许触发器名与表名分属不同 schema，两者均未在本轮做 |
| `ER_SP_UNDECLARED_VAR`(1327)、`ER_UNKNOWN_SYSTEM_VARIABLE`(1193) | 2 | 引用未声明变量 / 未知 `@@sysvar` | ✅ 已完成（2026-09-04）：两种情况其实本来就会报错，只是错误码不对（分别是通用的 1064/1105），不是"该报错而没报"；已改成精确匹配 MySQL 错误码，回归见 `test_031` |

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
- **C1 CALL 多结果集帧错乱** ✅ 已完成（2026-09-04）：见 §3 表格更新，根因是收尾 OK 包与结果
  集自身完成包共享同一个“还有更多结果”标志、语义被搞反。已用官方 `mysql` CLI 与 pymysql
  （含 `CLIENT_MULTI_STATEMENTS`）验证不再出现帧错乱/数据丢失/连接失联。回归见 `test_028`。
- **C2 CALL 非原子执行 + 事务语句** 🟡 **部分完成（2026-09-04）**：见 §3 表格更新。根因是两条
  独立的 PG 原生规则（proconfig 非空、prosecdef=true），各自都会强制 atomic=true。**已修复**
  第一条：例程元数据从 `pg_proc.proconfig` 迁移到 `plmysql` security label（`aux_mysql` 升到
  1.11），`SQL SECURITY INVOKER` 例程内 COMMIT/ROLLBACK 现在完全可用，回归见 `test_030`；
  `test_006/011/016` 同步更新为读 label 而非 proconfig。**未修复**第二条：MySQL 默认（不写
  `SQL SECURITY`）映射到的 `prosecdef=true` 本身触发 PG 的“SECURITY DEFINER 过程不能有事务
  语句”规则，这是 PG 与 MySQL 之间独立于第一条的语义鸿沟，`test_030` 显式钉住这一已知限制
  （断言仍报 1105，不是静默通过）。是否/如何处理第二条需要用户决定（维持现状 vs. 重新设计
  DEFINER 语义 vs. 权衡把默认改回 INVOKER），三个选项各自的代价见 §3。

### M11 — 类型系统
- **B2 `BINARY`/`CHARSET` 类型特性** ✅ 已完成（2026-09-04）：见 §3 表格更新——实际是一个未接线
  完整导致的服务端崩溃（SIGSEGV），已修复并验证四种书写顺序。回归见 `test_029`。
- **B1 ENUM/SET 类型**（~1–2 周，独立特性）：投入大，建议独立立项，非 SP 专属。

### M12 — 严格性/错误码对齐（打磨）
- **1327/1193 错误码对齐** ✅ 已完成（2026-09-04）：见 §3 表格更新，纯错误码修正（`mysSetPendingMySQLErrno`），
  不涉及语义变化。回归见 `test_031`。
- 1691（LIMIT 变量类型校验）：需要在 SP 执行路径里新增专门的 LIMIT 实参类型检查，比错误码对齐
  本身工作量大，语料里只 6 条，暂未做。
- **1361/1465（触发器建在 VIEW/临时表/系统 schema 上）** ✅ 已完成（2026-09-04）：见 §3 表格更新。
  回归见 `test_032`。
- **1415/1336（触发器返回结果集 / 函数触发器内动态 SQL）** ✅ **复测更正**：其实早就实现了，报告
  最初的"未强制"判断来自复测方法缺陷（没有真正触发执行），见 §3。
- 触发器语义（其余）：1313/1435/1442（~2–3 天，逐条按 MySQL 手册加 guard；1313 需要先核实 MySQL
  在 FUNCTION/PROCEDURE/TRIGGER 三种上下文里 RETURN 各自的真实限制，比单纯错误码替换复杂，见 §3）。
- LOCK TABLES 语义（1100/1099）、间接递归（1424）：投入较大、优先级低，可延后。

---

## 5. 测量局限与后续

- **未覆盖**：`sp.test` 中依赖 `eval`/`connect`/多连接的极少量用例；`sp-security`/`sp-error`
  等未纳入（可作为下一轮）。ENUM/字符集相关失败中，一部分是 openHalo 缺少对应类型域而非 SP
  引擎问题。
- **`WRONG_ERR` 需分层看**：约 102 条“真实不符”里，很大比例是“语义错误退化成 1064”，会随
  M9 的编译修复自动改善，不应单独计入 SP 引擎缺陷。
- **C1（CALL 帧错乱）已用官方 `mysql` CLI 与 pymysql 双重复核并彻底修复**：根因是 `CALL` 结果
  集自身的完成包与其后恒定紧随的收尾 OK 包共享同一个“还有更多结果”标志、语义被搞反，见
  §3 C1 行。
- 复现实验脚本与逐条结果 JSON 保存在会话 scratchpad：`mysqltest_parse.py` /
  `run_sp_compat.py` / `analyze.py` / `*.result.json`；可固化进 `src/test/mysql/` 作为持续
  兼容性看板。

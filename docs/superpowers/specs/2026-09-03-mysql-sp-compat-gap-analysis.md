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
| **A4** | **例程体内 `SET @@sysvar` / `SET sql_mode=…`** | 4 | 体内 `SET SQL_MODE='TRADITIONAL'` 被 plmysql 当成对未声明局部变量赋值 → “is not a known variable”(1064) | plmysql 的 `SET` 语句需区分：赋值本地变量 vs 设置系统/会话变量（透传给适配器的 `MysVariableSetStmt`）。这是设计文档 §7 风险 2 “SET 语句歧义”遗留的一半。**✅ 已修（2026-09-04，复用 `isSystemVariable()` 注册表，回归 `test_027`；本行归类此前未同步更新）** |

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
| **C2** | **过程内 `COMMIT`/`ROLLBACK` 运行期 1105** | **✅ 已彻底修复(2026-09-05,用户拍板方案 b)**。根因是 `ExecuteCallStmt()`(functioncmds.c)里两条各自独立、任一条都会把 `atomic` 强制改回 `true` 的 PG 原生规则。**规则1**(proconfig 非空)已于 2026-09-04 修复:plmysql 例程元数据迁移到专用 `plmysql` security label(aux_mysql 1.11)。**规则2**(prosecdef=true)本轮修复,思路是**让 plmysql 例程彻底不再使用 `pg_proc.prosecdef` 承载 SQL SECURITY**:`mys_plmysql_redirect_sql_security()`(mys_utility.c,CREATE 分发点,文法层不动、无 bison 风险)对 LANGUAGE plmysql 的例程摘掉原生 `security` 选项,把特性改记为 label 条目 `plmysql.sql_security=DEFINER/INVOKER`(prosecdef 恒 false → `ExecuteCallStmt` 不再强制原子;非 plmysql 例程如显式 `LANGUAGE plpgsql` 不受影响,仍走原生 prosecdef);运行期 `plmysql_switch_to_routine_definer()`(pl_handler.c)在 `plmysql_call_handler` 入口按 label(例程)/proconfig(触发器私有函数)里的 definer 元数据 `SetUserIdAndSecContext` 切换有效用户——**不带任何 security-restriction 位**:`StartTransaction()` 的 `Assert(prevSecContext == 0)` 检查的是整字,零位字照常通过,这正是 prosecdef 路径(`fmgr_security_definer` 会 OR 进 `SECURITY_LOCAL_USERID_CHANGE`)做不到的;正常/错误路径都经 `PG_ENSURE_ERROR_CLEANUP` 成对恢复,身份切换熬过 COMMIT、在例程内 SQLEXCEPTION handler 捕获错误后仍保持。配套语义一次补齐:MySQL 账户与 PG 角色 1:1 按名映射(登录即如此,adapter.c),definer 的 user 部分即角色名,缺角色报 MySQL 1449(CALL 期,与 MySQL 一致);**非 superuser 显式指定他人 definer 报 1227**(MySQL 的 SUPER 规则)——此前 definer 只是装饰性元数据、执行身份实为 pg_proc 属主,现在真的按 definer 执行,该检查从可选变为必需的防提权闸;`CURRENT_USER()` 在 DEFINER 例程内报 definer(effective-definer 覆盖栈,adapter/systemVar.c 状态 + mysm/user.c 读取;USER()/SESSION_USER() 仍报登录账户);MySQL 触发器的 definer(存于其私有函数 proconfig)同样生效。**MySQL 语义核对**:INVOKER 例程被 DEFINER 例程嵌套调用时按调用方有效身份(definer)执行,实现(不切换=继承当前 uid)与 MySQL 一致。旧例程(修复前创建、prosecdef=true)保持旧语义(按 proowner 执行、CALL 原子),`CREATE OR REPLACE` 即升级到新行为。遗留小项:aux_mysql 的 Security_type 显示列仍硬编码 'DEFINER'(修复前即如此,显式 INVOKER 例程显示不准),待随 aux_mysql 下一次版本升级一并修 | 全部完成:规则1 见 `aux_mysql--1.10--1.11.sql`;规则2 见 `mys_plmysql_redirect_sql_security()`/`mys_check_definer_privilege()`(mys_utility.c)、`plmysql_switch_to_routine_definer()`(pl_handler.c)、`mysPush/Pop/GetEffectiveDefiner()`(adapter/systemVar.c + mysm/user.c)。回归:`test_030`(默认/INVOKER 的 COMMIT/ROLLBACK,预期翻转)、`test_037`(新增,身份语义全量:CURRENT_USER/USER、COMMIT 存活、handler 捕获后存活、INVOKER、嵌套、触发器、1449)、`test_023`(断言改 label)、`test_034`(COMMIT 单语句体预期翻转) |

### D. 错误码与严格性缺口（负向，`MISSING_ERR`=openHalo 过于宽松）

按 MySQL 期望错误码归并（三份合计 48 条）：

| 期望错误码 | 次数 | 语义 | openHalo 现状 |
|---|---|---|---|
| `ER_TABLE_NOT_LOCKED` (1100/1099) | 8 | `LOCK TABLES` 后访问未锁表 | 不强制 LOCK TABLES 语义 |
| `ER_WRONG_SPVAR_TYPE_IN_LIMIT` (1691) | 6 | `LIMIT` 处用了错误类型的 SP 变量 | 不校验 |
| `ER_CANT_UPDATE_USED_TABLE_IN_SF_OR_TRG` (1442) | 3 | 触发器/函数修改正被触发语句使用的表 | 不强制 |
| `ER_SP_NO_RECURSION` (1424) | 3 | 经 `SELECT`/视图的间接函数递归 | ✅ **复测更正（2026-09-04）：其实早就正确处理间接递归**——`plmysql_check_recursion()`（`pl_handler.c`）遍历的是整条 plmysql 调用栈找同一个 `fn_oid`，不只看直接调用者；A 体内一句 `SELECT b()` 照样会把 B 压上同一条调用栈，B 再经 `SELECT a()` 回调 A 一样会被抓到。报告原先的判断有误，已用 A↔B 互相经 SELECT 调用的用例验证，回归见 `test_015` |
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
- **C2 CALL 非原子执行 + 事务语句** ✅ **已完成（2026-09-05）**：规则 1（例程元数据迁
  security label，aux_mysql 1.11）之后，规则 2 已按用户拍板的方案 (b) 修复——plmysql 例程
  不再以 `pg_proc.prosecdef` 承载 SQL SECURITY（改存 label 的 `plmysql.sql_security` 条目，
  `mys_plmysql_redirect_sql_security()`），运行期由 `plmysql_call_handler` 手动切换/恢复
  definer 有效用户（零 security-restriction 位，`StartTransaction()` 的断言不再触发）。
  MySQL 默认 DEFINER 例程内的 COMMIT/ROLLBACK 全部可用；同一改动把 1449（definer 缺
  角色）、1227（非 SUPER 指定他人 definer）、CURRENT_USER() 报 definer、触发器 definer
  生效四项语义一并补齐。详见 §3 C2 行。回归：`test_030`/`test_037`（新），`test_023`/
  `test_034` 预期翻转。

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
- **1424（间接递归）** ✅ **复测更正（2026-09-04）**：其实早就正确处理，见 §3 表格更新，回归见
  `test_015`。
- LOCK TABLES 语义（1100/1099）：投入较大、优先级低，可延后。

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

---

## 6. 本轮收尾（2026-09-04）

本轮（M9–M12 gap-driven 修复）到此结束。已完成项见 §3/§4 各自的 ✅ 标记（含三处"复测更正"：
1415/1336/1424 经复核确认早就实现，报告最初的负面判断来自不完整的复现方法）。剩余未完成项
**不是本轮遗留的待办，而是明确归档为后续独立立项的 backlog**：

| 项 | 归档原因 |
|---|---|
| 1313（RETURN 不允许出现在触发器体内） | 已实测尝试：直接在 plmysql 语法层拦截会连带拦住触发器包装层自动注入的 `RETURN NEW`（PG 原生触发器函数协议要求），需要改成在包装之前扫描原始 MySQL 触发器体文本，工作量与风险高于本轮其余项 |
| 1442（触发器/函数内更新正被触发语句使用的表） | 需要新增"当前 DML 语句正在修改哪张表"的调用链级运行时追踪，是新基础设施，不是局部检查 |
| 1691（LIMIT 处变量类型校验） | 需要在 SP 执行路径新增专门的 LIMIT 实参类型检查 |
| 1435（触发器与表分属不同 schema） | 当前语法根本不支持给触发器名单独指定 schema（`CREATE TRIGGER` 的 `name` 产生式不接受 qualified name），要做需要先扩展语法 |
| LOCK TABLES 语义（1100/1099） | 独立的大特性（会话级锁追踪与全语句类型强制），不是 SP 专属 |
| B1（ENUM/SET 类型） | 报告最初就定性为独立立项，非 SP 专属 |

---

## 7. 编译通过率冲刺至 80%（2026-09-04，第二轮）

用户明确指示："先把现在能做的功能做了，先尽量让 create procedure，create function 编译
通过率起来 80%，然后再考虑还有哪些功能能做，再能达到 85% 最好"——本轮聚焦纯工程、无产品
语义取舍的编译期缺口，不涉及 §6 归档的 backlog 项。对 `sp.test`/`trigger.test`/
`sp_trans.test` 三份语料合计的 `CREATE PROCEDURE`+`CREATE FUNCTION` 编译通过率：

| 阶段 | 编译通过率 | 说明 |
|---|---|---|
| 本轮开始前（M9 记录基线，仅 procedure） | 76.0%（272/358） | 见 §4 M9 |
| +A1 flow-control/DDL 单语句体 | 78.4%（395/504） | 见下 |
| +REPEAT() 函数调用误判修复 | 78.6%（396/504） | 顺带修复，见下 |
| +`#` 注释 / `SQLSTATE VALUE` | 79.6%（401/504） | 见下 |
| +ALTER/START TRANSACTION/COMMIT 单语句体 | **80.16%（404/504）** | 已达标 |
| +带标签单语句体（2026-09-05） | **81.75%（412/504）** | 见上方"带标签"行；同轮修复 CALL handler 结果集挂起（见下），带执行重放三文件 TIMEOUT=0 |

**已完成的四项修复**（均已提交，回归见对应 `test_0NN`）：

1. **裸 WHILE/REPEAT/IF/CASE/CREATE/DROP 作为例程整个函数体**（无外层 `BEGIN...END`）：
   `mysql_single_stmt_body_leader` 从 7 个候选扩到 14 个；`mys_capture_routine_body()`
   新增 `leading_uncounted_kind` 参数处理无外层 BEGIN 时的嵌套边界识别；`CASE` 单独加
   `MYS_LEADING_CASE` 哨兵处理后缀截断。回归：`test_034`。
2. **`REPEAT(str,count)` 内建函数与 `REPEAT` 循环关键字共用一个 token 导致误判**：裸
   REPEAT 循环体内如果调用了同名函数，会让上一条修复的"计数归零"判据永远凑不齐，报
   "unterminated routine body: missing END"。因为 REPEAT 循环从不会在关键字后紧跟 `(`
   （其 UNTIL 条件写在循环体末尾），而 IF/WHILE 的条件本身可以带括号，所以只对 REPEAT
   做了这个一次性 lookahead 排除，IF/WHILE 维持原有保守策略。顺带修好了 `test_002`
   里一个更窄的已知局限（CASE 表达式内联 REPEAT() 时自身的裸 END 被误判）。回归：
   `test_002`、`test_034`。
3. **`#` 单行注释完全不识别**（不止例程体内，任何 MySQL 协议语句里都不认，因为 `#`
   被当成了 PG 风格自定义操作符的合法字符）；以及 **`DECLARE ... CONDITION FOR
   SQLSTATE VALUE '...'`**（可选 VALUE 关键字）不被接受。两个缺口是在同一条语料
   （`sp.test` 的 `hndlr1` 过程）里一起发现的。回归：`test_035`。
4. **ALTER/START TRANSACTION/COMMIT 作为例程整个函数体**：和 CREATE/DROP 一样的模式，
   补进 `mysql_single_stmt_body_leader` 即可，捕获逻辑复用已有的"扫到下一个顶层分号"
   兜底路径。COMMIT 单语句体的 CALL 当时仍撞见 C2（默认 DEFINER 下事务控制受阻）并
   以 1105 钉住；C2 规则 2 已于 2026-09-05 修复（见 §3），`test_034` 的该断言已翻转为
   COMMIT 成功，START TRANSACTION 仍钉 1235（PG 过程只支持 COMMIT/ROLLBACK，引擎层
   限制，与 security 模式无关）。

**剩余未达标的约 100 条失败，按体量排序**：

| 类别 | 条数 | 归类 |
|---|---|---|
| VIEW 依赖阻塞 DROP FUNCTION（1304） | 30 | §6 已归档的产品/语义取舍问题；用户已明确决定**维持现状，不修** |
| ~~带标签的循环/块作为函数体（`label: WHILE ...`）~~ | ~7 | ✅ **已完成（2026-09-05）**：`mysql_routine_body` 新增 `IDENT ':' mysql_single_stmt_body_leader` 与 `IDENT ':' BEGIN_P` 两条产生式（bison 冲突数不变，仍 48），捕获子串从标签起始；`mys_capture_routine_body()` 在最外层 closer（裸 `END` 与 seed 路径的 `END WHILE/LOOP/REPEAT`）消费可选标签回声，回声不再漏成 bison lookahead。回归见 `test_036` |
| `FLUSH` 类语句（TABLES/LOGS 等） | ~14 | openHalo 目前完全没有 FLUSH 语句，不是单纯加 leader 能解决的，需要新增一整类语句支持，超出 SP 专属范围 |
| 长 DEFINER 主机名（60+ 字符） | ~4 | 疑似扫描器缓冲区长度限制，MySQL 自身语料里的极端测试用例，真实场景价值低 |
| 带括号的 SELECT 作为函数体语句 | ~3 | 不在 mys_gram.y 捕获层，而是 plmysql 自己的语句文法（pl_gram.y）不接受 `(SELECT ...) UNION ...` 形态 |
| `/*!50003 ...*/` 版本门控注释 | ~3 | MySQL 特有的条件注释语法，需要专门处理 |
| 长尾个例（CHECKSUM/REPAIR/ANALYZE/TRUNCATE/RESET/HANDLER READ 等） | ~10 | 各自需要判断 openHalo 是否已支持该语句类型，逐条工作量小但数量分散 |

**另发现一个与编译通过率无关的运行期 bug——✅ 已定位并修复（2026-09-05）**：例程体含嵌套
`DECLARE CONTINUE HANDLER FOR SQLEXCEPTION` 时，`CALL` 该例程会挂起数十秒到数分钟。根因：
`pl_gram.c` 把**所有** handler 动作体里的裸 SELECT 都计入 `n_resultsets`（静态直线计数），运行期
handler 按条件触发、实际推送数少于计数，`resultsets_sent < n_resultsets` 使
`plmysql_push_execsql_resultset()` 不恢复 `moreResultsFlag`，CALL 恒定尾随的收尾 OK 包便谎报
"还有结果集"（wire 抓包实证：收尾 OK 的 status 位 0x000a 含 MORE_RESULTS_EXISTS），客户端
永远等待第二个结果集——语料重放中 19 条 CALL（h_es/h_ss/h_xs 全系及多个 bugNNNN 过程）均
如此失步。修复：每次结果集推送发出后立即恢复 `moreResultsFlag = outer_more_results_flag`，
完全不再依赖静态计数（计数对循环多次推送只会少算、对条件 handler 只会多算，两端都不可信）；
结果集自身 EOF 恒报"还有更多"（因为收尾 OK 恒随后）的不变式保持不变。回归见 `test_028` 的
`run_conditional_handler`（SSCursor 逐结果集读取 + 后续语句连接保活断言）。修复后三份语料
带执行重放 TIMEOUT=0，其余 DESYNC 均为独立问题（`SHOW CREATE` 输出二进制字节的
UnicodeDecodeError ×4、`proc_33618` 断连 ×1，另行归档）。

以上各项如需推进，建议作为独立 issue/里程碑分别评审，而非在这份报告的框架下继续挂起。
---

## 8. 补完轮(2026-09-05):procedure/function/trigger 批量落地

依三份方案文档(trigger-completion / beyond-sp / procfunc-completion)实施,全部合入
`feature/mysql-stored-procedure-m1`:

- **文法/词法**(77f0db8952):leader 列表 17→24(ANALYZE/TRUNCATE/RESET/FLUSH/
  CHECKSUM/REPAIR/OPTIMIZE);FLUSH 全族解析并按 LOCK TABLES 先例 no-op;
  CHECKSUM/REPAIR/OPTIMIZE TABLE 走 mysql.* 函数(真校验和/状态行);
  DEFINER host 不再被 63 字节截断(裸 host 与单引号 host 两条新路径,反引号
  host 仍截断=已知限制);DEFINER=CURRENT_USER 经 RoleSpec 链解析为创建者
  (marker 机制,CREATE/ALTER ROLE/USER/GROUP 拒绝 marker);限定名触发器
  (mysqldump 形态)进入文法;FOLLOWS/PRECEDES 解析并记录元数据。
  %expect 48→52(RESET 语句体 vs PG RESET 特性等,默认解析均符合预期),
  bison 新增关键词走 %token 块 + 两张关键词表 + kwlist.h + check 脚本四处同步。
- **引擎**:括号 SELECT 语句体(is_select 同步识别,结果集不吞);体内
  START TRANSACTION=COMMIT 同义;SAVEPOINT/ROLLBACK TO/RELEASE 落在内部
  子事务栈(handler 块 wrapper 协议:stmt_subxact_released;外层调用帧退出时
  释放保存点保住适配器提交;未知保存点 1305;COMMIT 释放全部);1691 LIMIT
  变量类型校验(查 plan sources 的 query_list 的 limitCount/limitOffset 的
  PARAM_EXTERN,注意 list 元素是 CachedPlanSource 不是 Query);1422 编译期
  首词嗅探(CREATE/DROP TEMPORARY 豁免)。
- **服务端**:1313 扫描原始触发器体(绕开包装层注入的 RETURN NEW);
  1304 剪依赖(DROP FUNCTION/PROCEDURE/TABLE 前删视图的 pg_rewrite NORMAL
  依赖行,视图失效不阻塞,2BP000 补 sqlstate 映射);触发器私有函数名编码
  创建序号 `__mysql_trigger_<seq>_<name>`(同事件按创建序触发;DROP 匹配双
  兼容);1435 限定名 schema 校验;1227/1449 已随 C2 落地。
- **显示**:SHOW CREATE 按label补 SQL SECURITY INVOKER(aux_mysql 1.12,
  get_proc_def/get_func_def 以 1.9--1.10 最新定义为基)。

**度量**:探针固化于 `src/test/mysql/corpus/compile_rate_probe.py`
(方法=§1/§2 口径,只统计定义语句)。新口径基线:三份语料 CREATE
PROCEDURE/FUNCTION 合计 520 条,通过 445 = **85.58%**;剔除 ~15 条因
mysqltest 建库上下文缺失(1049)的语句后约 88%。距离旧口径 504 分母不可
直接比较(解析器差异)。剩余失败桶:ENUM/SET 1091(6)、版本门控注释体内
1064(需 pl_scanner 支持 /*!NNNNN)、8 次段错误(BUG#25411 `/*!99999`
体、非 UTF-8 变量名体等,已归档待查)、mysqltest 上下文缺失(1049)。

**新构建陷阱**:plmysql 的 Makefile 不跟踪头文件依赖——改 plmysql.h 后必须
`rm src/pl/plmysql/src/*.o` 全量重编,否则旧 .o 结构体错位导致随机崩溃;
mys_utility.c(文本包含)同理需 rm tcop/utility.o。

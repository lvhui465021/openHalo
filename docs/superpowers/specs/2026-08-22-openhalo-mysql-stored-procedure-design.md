# openHalo MySQL 存储过程 / 存储函数支持 — 架构设计

- 日期：2026-08-22
- 基线代码：openHalo（PostgreSQL 14.23 分支）master @ 90fc8d777c
- 对标标准：MySQL 5.7 Reference Manual §13.1.16 / §13.2.1 / §13.6.x / §13.7.5.x
- 参考实现：Babelfish for PostgreSQL 4.8.0（PG 16.11 基线）

## 1. 背景与目标

openHalo 通过 `database_compat_mode = 'mysql'` + 独立 MySQL 协议监听器（3306 端口）+ `aux_mysql` 扩展，让 MySQL 客户端可以直接连接一个 PostgreSQL 内核。当前 MySQL 兼容模式下，`CREATE PROCEDURE` / `CREATE FUNCTION` 只能声明 `LANGUAGE SQL` 且过程体只能是平铺 SQL 语句列表——没有变量、没有流程控制、没有游标、没有异常处理。这意味着：

- 无法把真实业务系统里的 MySQL 存储过程原样迁移过来
- `mysqldump` 导出的过程/触发器在 openHalo 上导入即失败（语法层面过不去）
- `CALL proc(@out_param)` 的 OUT 参数不会真正回写调用者的 `@变量`

本设计的目标：让 openHalo 在 MySQL 协议下支持 **MySQL 5.7 语义的存储过程与存储函数**（`CREATE PROCEDURE`/`CREATE FUNCTION`、完整流程控制、游标、条件处理、`SIGNAL`/`RESIGNAL`），并打通 `CALL` 的 OUT/INOUT 参数回写与多结果集协议。

### 作用域

- **仅 MySQL 协议会话可创建和调用**（`MyProcPort->protocol_handler == T_MySQLProtocol`）。PostgreSQL 协议（5432/psql）侧调用 `plmysql` 例程报错，提示"请通过 MySQL 协议使用"。
- **例外：创建期不做协议限制**，仅做语法/语义校验。原因：`pg_dump`/`pg_restore`、逻辑复制等工具可能在非 MySQL 协议连接下重放 DDL；若创建期也拦截，备份恢复链路会断裂。
- 存储函数（`CREATE FUNCTION`）与存储过程（`CREATE PROCEDURE`）共用同一套过程语言引擎，本期一并实现。
- 触发器支持限定为 MySQL 5.7 的行级 DML 子集（`BEFORE`/`AFTER` + 单个 `INSERT`/`UPDATE`/`DELETE` + `FOR EACH ROW`；详见 §4.10）。
- 不追求 MySQL 8.0 新增语法（如 `CHECK` 约束错误码、窗口函数相关差异）。

### 非目标

- 不做游标的 `SCROLL`/双向移动（MySQL 游标本身只读不可滚动，天然子集）
- 不做 `max_sp_recursion_depth` 之外的存储过程性能优化
- 不做字节码/GOTO 执行引擎（MySQL SQL/PSM 无裸 `GOTO`，树形解释器足够，见 §5）

---

## 2. 现状盘查

### 2.1 语法层

MySQL 兼容语法在 [`mys_gram.y`](../../../src/backend/parser/mysql/mys_gram.y)（24000+ 行，PG14 `gram.y` 的 MySQL 方言扩展版）。

- `CREATE FUNCTION`/`CREATE PROCEDURE` 产生式存在（`mys_gram.y:11069-11123`），但 `opt_routine_body`（`mys_gram.y:11582-11601`）只接受：
  - `RETURN a_expr`（单表达式）
  - `BEGIN ATOMIC routine_body_stmt_list END`（PG12+ SQL 标准复合体，`routine_body_stmt` 只能是普通 `stmt`）
- `createfunc_opt_item` 里唯一可解析的 `LANGUAGE` 子句是字面量 `LANGUAGE SQL`（`unused_func_opt_item`, `mys_gram.y:11555-11561`），且解析后**丢弃**（`$$ = NULL`）。没有 `AS $$...$$` 语法，没有 `LANGUAGE plpgsql` 等其他语言选项。
- `IN`/`OUT`/`INOUT`/`VARIADIC` 参数模式语法完整（`func_arg`, `mys_gram.y:11248-11288`）。
- `CALL` 语句存在（`mys_gram.y:1129-1136`，标准 `CallStmt`）。
- `ALTER/DROP/COMMENT ON PROCEDURE|FUNCTION`、`SHOW CREATE PROCEDURE`、`SHOW PROCEDURE STATUS` 均存在（`mys_gram.y:3598-3771` 等），是可用的周边设施。
- **`DEFINER = user` 只接在 `CREATE VIEW` 上**（`opt_definer`, `mys_gram.y:11130`, 使用点仅 `mys_gram.y:13795/13808`），例程产生式未引用，mysqldump 导出的 `CREATE DEFINER=... PROCEDURE` 语法过不去。
- MySQL 过程语言关键字状态（全文 grep 核实）：

  | 关键字 | 状态 |
  |---|---|
  | `DELIMITER`（服务端指令）、`SIGNAL`、`RESIGNAL` | 完全不存在（关键字表无条目） |
  | `DECLARE <var> type`（局部变量）、`DECLARE ... HANDLER FOR` | 不存在 |
  | `LOOP`/`WHILE`/`REPEAT`、`ITERATE`/`LEAVE`、`SQLSTATE`/`SQLEXCEPTION` | 仅作为保留关键字出现在分类表里，**零语法产生式**（"死关键字"） |

- `DETERMINISTIC` 被映射为 `IMMUTABLE`（`common_func_opt_item`, `mys_gram.y:11525`）——**语义错误**：MySQL `DETERMINISTIC` 只保证"同输入同输出"（用于 binlog 复制安全判定），不保证不访问表；PG `IMMUTABLE` 承诺不访问数据库，会被 planner 常量折叠。应映射为 `STABLE`。

### 2.2 目录 / 元数据层

`contrib/aux_mysql/aux_mysql--1.3--1.4.sql` 提供三个只读视图，全部投影自 `pg_proc`：

- `mysql.proc`（`:5191`）、`mys_informa_schema.procedures`（`:3913-3928`）、`mys_informa_schema.routines`（`:5059`)
- `ROUTINE_BODY`/`language` 均为 `'SQL'`；这是 MySQL 5.7 对存储例程公开的规定值，不应暴露内部 `plmysql` 语言名
- aux_mysql 1.7 起，`ROUTINE_COMMENT`/`mysql.proc.comment` 投影 `pg_description`，与 `CREATE ... COMMENT` 的持久化位置一致
- `mysql.get_proc_def()`/`get_func_def()`（`:3765`）是 plpgsql 写的 `pg_proc` 行→`SHOW CREATE` 文本格式化函数，非独立存储

无独立 MySQL 例程元数据表；`sql_mode` 快照、handler 声明链等 MySQL 特有信息目前无处存放。

### 2.3 执行引擎

`src/pl/plpgsql/` 是未经修改的 PG14 原版 plpgsql，**与 MySQL 侧用户例程完全脱钩**。唯一使用点是内部 C 代码直接构造 `CreateFunctionStmt` 生成 `AUTO_INCREMENT`/`ON UPDATE CURRENT_TIMESTAMP` 触发器函数（[`createTriggerFunc()` mys_parse_utilcmd.c:849-938](../../../src/backend/parser/mysql/mys_parse_utilcmd.c)），绕过 SQL 文本解析直接拼节点树。这证明 plpgsql 编译/执行链路在 build 中完整可用，但 SQL 层没有开放给最终用户。

`src/pl/` 目录本身（`plperl`/`plpgsql`/`plpython`/`tcl`）与上游 PG 一致，无 MySQL 专属 PL。

### 2.4 CALL 链路与协议层

- `mys_transformCallStmt()`（[`mys_analyze.c:1900-2215`](../../../src/backend/parser/mysql/mys_analyze.c)）正确按 `pg_proc.proargmodes` 拆分 IN/OUT/INOUT 参数，并识别 `@变量`（`UserVarRef`）作为 OUT/INOUT 目标，构建 `stmt->outargs`（`:2205`）。
- `mys_utility.c:380-381` 把 `T_CallStmt` 分派给**原生未修改**的 `ExecuteCallStmt()`（`functioncmds.c:2207-2379`）。该函数只是把过程返回的 `RECORD` 当普通结果集行发给 `DestReceiver`，**从不读取 `stmt->outargs`**。
- 全代码库中 `outargs` 只有两处消费：`functioncmds.c:2404-2417`（仅用于类型修正 `CallStmtResultDesc`），以及构建它本身的 `mys_analyze.c`。**没有任何代码把返回值写回 `@变量`**。
- openHalo 已有可直接复用的回写原语：[`mysSetUserVarForPl()`](../../../src/backend/commands/mysql/mys_uservar.c:142)，目前被 `SELECT ... INTO @var` 使用（[`mys_utility.c:1686`](../../../src/backend/tcop/mysql/mys_utility.c)）。**缺的只是把它接到 CALL 路径上**，不是要重新设计回写机制。
- `COM_STMT_PREPARE` 已把 `T_CallStmt` 加入白名单（[`mysUtilityCanPrepare()` mys_prepare.c:270-271](../../../src/backend/commands/mysql/mys_prepare.c)），`CALL` 可作为预处理语句执行。
- **多结果集信号位 `moreResultsFlag` 是真实生效的，但只覆盖顶层批处理**：[`postgres.c:1122-1140`](../../../src/backend/tcop/postgres.c) 在 MySQL 协议下处理多语句 `COM_QUERY` 时置位 `0x0008`（对应 [`HALO_SVR_MORE_RESULTS_EXISTS`](../../../src/include/adapter/mysql/common.h:98)）。**单个 `CALL` 内部产生多个结果集（未被 INTO 消费的裸 SELECT）没有任何触发点**——因为过程体目前根本不能包含多条语句。

### 2.5 引擎级可插拔架构（重要设计前提）

openHalo 已经实现了按会话切换的解析/执行引擎机制，新增语言可以直接复用这个扩展点：

| 引擎 | 切换点 | MySQL 分支 |
|---|---|---|
| `parserengine` | [`parsereng.c:38-64`](../../../src/backend/parser/parsereng.c) | `GetMysParserEngine()` |
| `executorengine` + `ProcessUtility_hook` | [`executor_engine.c:40-70`](../../../src/backend/executor/executor_engine.c) | `GetMysExecutorEngine()` |

切换条件：`database_compat_mode == MYSQL_COMPAT_MODE` 且 `MyProcPort->protocol_handler == T_MySQLProtocol`。`ParserRoutine`（[`parserapi.h:98-144`](../../../src/include/parser/parserapi.h)）已抽象出 30+ 个可替换钩子（含 `transformCallStmt`），是本设计要接入的既有扩展点，不需要新建切换机制。

### 2.6 错误码映射现状

[`errorConvertor.c`](../../../src/backend/adapter/mysql/errorConvertor.c) 维护一个哈希表，键为 PG `MAKE_SQLSTATE()` 编码整数，值为 MySQL errno，单向（PG→MySQL），唯一调用点在发送错误包时（`adapter.c:5419`）。实际解码 17 条：

| 类别 | 数量 | 详情 |
|---|---|---|
| 正确 | 10 | 如 `23505→1062`、`42P01→1146`、`23502→1048` 等常见约束/对象错误 |
| **死条目**（键写成了 MySQL errno 而非 SQLSTATE，永不命中） | 3 | `initErrorCode(1064,1265)` / `(1292,1366)` / `(1364,1048)` |
| **映射错误** | 4 | `42601`(语法错误)→1478 应为 1064；`22P02`→1064 应为 1366/1292；`23514`→1264（MySQL 5.7 无 CHECK 约束）；`P0001`→1264 见下 |

**关键阻塞点**：`P0001`（`ERRCODE_RAISE_EXCEPTION`，plpgsql `RAISE`/`SIGNAL` 落地后的默认 SQLSTATE）当前硬映射到 `1264`。一旦 `SIGNAL` 语句上线，所有未显式指定 `MYSQL_ERRNO` 的 `SIGNAL SQLSTATE '45000'` 都会被错误上报为"数值超范围"而非用户预期的错误。必须在 `SIGNAL`/`RESIGNAL` 实现里让 `MYSQL_ERRNO` 直接穿透，绕开这张表（详见 §4.8）。

**兜底泄漏**：未命中时原样返回 PG 编码整数（`errorConvertor.c` 尾部 `return haloErrorCode;`），MySQL 客户端会收到类似 `16777240` 的非法 errno。应改为兜底 `1105`(`ER_UNKNOWN_ERROR`)。

### 2.7 mysqldump 触发器导入现状（旁证）

历史上 [`tools/convert_mysqldump_file.py:173-190`](../../../tools/convert_mysqldump_file.py) 的未接入 `convertTrigger()` 辅助函数会生成裸 PG `CREATE FUNCTION ... RETURNS TRIGGER`，当时无法解析。2026-08-30 已清理：该死函数删除，触发器 DDL 原样透传；另修复其 Python 版本检查（字符串比较把 ≥3.10 全部误判为"版本过低"而退出）。配套地，服务端现支持 MySQL 可执行注释（`mys_scan.l` 的 `/*!版本门 ...*/`，≤5.7 门执行、更高门跳过），并补齐单语句触发器体捕获在 EOF 处把尾部 `*/` 吞进存储体的问题——mysqldump 导出的脚本现在可直接导入（黑盒回归见 §8）。

---

## 3. MySQL 5.7 语法对标矩阵

图例：✅ 已支持 ⚠️ 部分/有缺陷 ❌ 缺失　|　难度：低/中/高（本设计给出的实现难度，非此前粗判）

### A. 例程定义 DDL（§13.1.16）

| 语法项 | 现状 | 难度 |
|---|---|---|
| `CREATE PROCEDURE`/`CREATE FUNCTION ... RETURNS` | ✅ | — |
| `IN`/`OUT`/`INOUT` 参数 | ✅ | — |
| `DEFINER = user` | ✅ `user@host` 原文记录于 `pg_proc.proconfig`（`plmysql.definer`），`SHOW CREATE`/`mysql.proc`/information_schema 视图按记录值展示；执行归属仍为创建者（invoker-based） | — |
| `COMMENT 'string'` | ✅（持久化到 `pg_description`，并由 aux_mysql 1.7 元数据视图公开） | — |
| `LANGUAGE SQL` | ✅ MySQL no-op 特性；例程仍选定 `plmysql` | — |
| `[NOT] DETERMINISTIC` | ✅ 映射为 STABLE / VOLATILE | — |
| `CONTAINS SQL｜NO SQL｜READS/MODIFIES SQL DATA` | ✅ 显式值写入 `pg_proc.proconfig` 的 `plmysql.sql_data_access`，并由 `mysql.proc`、`information_schema.ROUTINES` 和 `SHOW CREATE` 展示；未指定时按 MySQL 默认 `CONTAINS SQL` | — |
| `SQL SECURITY DEFINER/INVOKER` | ✅ 原样映射到 PG 原生 `prosecdef`；缺省（不写该子句）时按 MySQL 默认取 DEFINER，而非 PG 自身默认的 INVOKER（2026-08-30 修，`mys_apply_default_sql_security()`）。**未做**：`DEFINER='user'@'host'` 的用户名目前只写入 `plmysql.definer` 元数据供展示，不会把 `pg_proc` 的属主（owner）改成对应 PG 角色，因此 `SECURITY DEFINER` 例程实际仍以创建者的权限运行，而不是 DEFINER 具名用户——这是经过讨论后有意保留的范围外项，见 §7 风险 7 | — |
| **裸 `BEGIN...END` 过程体** | ✅（M1，§4.2） | — |
| `ALTER`/`DROP {PROCEDURE｜FUNCTION}` | ✅ | — |

### B. 调用（§13.2.1）

| 语法项 | 现状 | 难度 |
|---|---|---|
| `CALL sp(args)` | ✅ | — |
| **OUT/INOUT 回写 `@var`** | ✅（M5，§4.6） | — |
| **过程体多结果集**（裸 `SELECT`、`EXECUTE` 预处理语句） | ✅（M5，§4.7；`plmysql_push_execsql_resultset()`, `pl_exec_ext.c`） | — |

### C. 复合语句与流程控制（§13.6.1–13.6.5）

| 语法项 | 现状 | plpgsql 映射目标 |
|---|---|---|
| `[label:] BEGIN...END [label]` | ✅ 原生 `label:` 拼写与 `<<label>>` 双拼写均已支持（label 仅限普通标识符，与 MySQL 一致） | `PLMySQL_stmt_block` |
| `DECLARE v[,v2] type [DEFAULT expr]` | ✅（M1，支持一条声明多变量） | `PLMySQL_var` |
| `SET var = expr` | ✅（M1 本地变量；`SET @uservar = expr` 于本次会话补上，透传给 SPI） | `PLMySQL_stmt_assign` |
| `SELECT ... INTO var`（例程内） | ✅（M1） | `PLMySQL_stmt_execsql`(into) |
| `IF/ELSEIF/ELSE/END IF` | ✅（M1） | `PLMySQL_stmt_if` |
| `CASE ... END CASE` | ✅（M2） | `PLMySQL_stmt_case` |
| `[label:] LOOP...END LOOP` | ✅ `label:`/`<<label>>` 双拼写，循环语义已完成 | `PLMySQL_stmt_loop` |
| `[label:] WHILE c DO...END WHILE` | ✅ `label:`/`<<label>>` 双拼写，循环语义已完成 | `PLMySQL_stmt_while` |
| `[label:] REPEAT...UNTIL c END REPEAT` | ✅ `label:`/`<<label>>` 双拼写，循环语义已完成 | `stmt_loop` + 尾部 exit |
| `LEAVE label` / `ITERATE label` | ✅（M2） | `stmt_exit`(is_exit=true/false) |
| `RETURN expr`（FUNCTION） | ✅（M1） | `PLMySQL_stmt_return` |

### D. 游标（§13.6.6）

MySQL 游标是只读、不可滚动、仅例程内可用——PG 游标的真子集。

| 语法项 | 现状 |
|---|---|
| `DECLARE c CURSOR FOR select_stmt` | ✅（M3） |
| `OPEN c` / `FETCH ... INTO vars` / `CLOSE c` | ✅（M3） |
| **游标耗尽 → `NOT FOUND` 可捕获条件** | ✅（M3/M4，与 HANDLER 联动） |

### E. 条件处理（§13.6.7）

| 语法项 | 现状 |
|---|---|
| `DECLARE cond CONDITION FOR {errno｜SQLSTATE}` | ✅（M3） |
| **`DECLARE {CONTINUE｜EXIT} HANDLER FOR conds stmt`** | ✅（M4，§4.5） |
| 条件类：`SQLSTATE 'x'` / errno / `SQLWARNING` / `NOT FOUND` / `SQLEXCEPTION` | ✅（M4） |
| `SIGNAL cond [SET items]` / `RESIGNAL` | ✅（M4，§4.8） |
| `GET [CURRENT｜STACKED] DIAGNOSTICS` | ✅（M4） |
| **`DECLARE` 声明顺序校验**（变量/条件→游标→处理程序） | ✅（本次会话修复：变量/游标声明此前从未调用顺序检查；HANDLER 动作体若自身是嵌套 `BEGIN...END`，会把外层块的顺序状态清零，已改为保存/恢复栈） | — |

### F. 内省（§13.7.5）

| 语法项 | 现状 |
|---|---|
| `SHOW CREATE {PROCEDURE｜FUNCTION}` | ✅ 语法存在，输出依赖 `prosrc` 存什么 |
| `SHOW {PROCEDURE｜FUNCTION} STATUS` | ✅ |
| `information_schema.ROUTINES` / `mysql.proc` | ✅ `language`/`ROUTINE_BODY = 'SQL'`；COMMENT、创建/修改时间、`sql_mode` 快照、SQL data access 与原始 `DEFINER user@host` 均由 aux_mysql 投影 `pg_proc.proconfig` |

### G. 运行时语义（非语法但须对齐）

| 语义 | MySQL 5.7 行为 | 现状 |
|---|---|---|
| `sql_mode` 快照 | 创建时记录，执行时应用 | ⚠️ 已在例程调用时把函数级 GUC 快照同步到适配器运行时状态，支持空快照、嵌套 CALL 与 ERROR 清理；`STRICT_TRANS_TABLES`/`STRICT_ALL_TABLES` 已驱动现有数值转换路径。扫描/语法重写类 mode 与 MySQL DML warning 行为仍未全部映射 |
| 过程递归 | 受 `max_sp_recursion_depth`，默认 **0=禁止**，范围 0–255 | ✅ 会话变量已实现并在调用栈检查（超限 1456） |
| 函数递归 | MySQL 禁止 | ✅ 拒绝重入（1424） |
| 函数内表访问限制 | 不能修改调用语句正在读写的表 | 可选，本期不做 |
| 函数返回结果集 | 报错 1415 | ✅ 裸 `SELECT` 以 1415 拒绝 |
| `PREPARE/EXECUTE` 作用域 | PROCEDURE 内可用，FUNCTION/TRIGGER 内不可 | ✅ 函数/触发器编译期拒绝（1336） |
| `DECLARE` 顺序约束 | 变量/条件 → 游标 → 处理程序 | ✅ 本次会话修复（见 §E） |

**本次会话另修复的运行时缺陷**（均不改变本节的语法覆盖范围，但影响正确性）：
- `SIGNAL SQLSTATE 'xxxxx'`（自定义、未在错误码表中登记的 SQLSTATE）之前在发包时被硬编码替换为 `"HY000"`，客户端拿不到真实 SQLSTATE；`adapter.c` 的 `sendErrorMessage()` 改为发送 `unpack_sql_state(edata->sqlerrcode)`。§4.8 提到的"错误码→MySQL 规范 SQLSTATE"反向映射也已补齐（2026-08-30）：`errorConvertor.c` 新增 17 条 PG SQLSTATE→MySQL 规范 SQLSTATE 键值（`mysCanonicalizeSqlState()`，与 `pl_exec_ext.c` 的 27 条 errno 三元组人工审核口径一致），`sendErrPacket()` 发包时把命中的 PG 状态改写为 MySQL 规范值（如 `42P01→42S02`、`23505→23000`）；`SIGNAL`/`RESIGNAL` 选择的自定义状态（`45000`、`A0001` 等）不是键，仍原样回传。

---

## 4. 架构设计

### 4.1 总体分层与数据流

```
mysql client (3306)
   │  COM_QUERY: "CREATE PROCEDURE p(IN x INT) BEGIN ... END"
   ▼
mys_gram.y  CreateFunctionStmt
   │  routine body 原文整体截取 → prosrc 字符串
   │  language 固定为 "plmysql"
   ▼
CreateFunction() [原生 functioncmds.c，不修改]
   │  → pg_proc 行（prolang = plmysql 的 oid）
   ▼
plmysql_validator()  [新增 PL handler，CREATE 时自动触发]
   │  用 plmysql 编译器解析 prosrc → PLpgSQL_function 树（结构体复用 plpgsql 命名）
   ▼
运行时 CALL p(1, @out)
   │
mys_transformCallStmt()  [已存在，构建 outargs]
   ▼
ExecuteCallStmt() [原生]  →  执行 plmysql_call_handler()
   │                              │
   │                              ├─ 裸 SELECT → DestRemote 直送 socket + moreResultsFlag 回填
   │                              └─ 返回 RECORD(out params)
   ▼
mysSetUserVarForPl() 灌回 @out   [已存在的函数，新增调用点]
```

### 4.2 语法层：过程体原文捕获

不教 `mys_gram.y` 认识 `DECLARE`/`LOOP`/`HANDLER` 等任何过程语言语法。参考 Babelfish `gram-tsql-rule.y:4145-4187` 的 `tokens_remaining` 技巧：在 `CreateFunctionStmt` 产生式里新增一条中间动作，从当前 token 的原文偏移开始，持续消费 token 直到语句结束（`;`），但不解释语义，最后用 `scanbuf` 做原文 substring。

```c
/* mys_gram.y 新增产生式（示意） */
mysql_routine_body:
    BEGIN_P { $$ = capture_raw_tokens_until_matching_end(yyscanner); }
```

需要处理嵌套配对计数（`BEGIN/END`、`IF/END IF`、`LOOP/END LOOP`、`CASE/END CASE`、`WHILE/END WHILE`、`REPEAT/END REPEAT`）以正确定位最外层 `END`，因为服务端收到的是 mysql 客户端按 `DELIMITER` 切分好的完整单条语句（`DELIMITER` 本身**不需要**服务端实现——现状盘查已确认它由客户端/`convert_mysqldump_file.py` 消化，参见 §2.7）。

捕获后的字符串塞入 `CreateFunctionStmt.options` 的 `"as"` DefElem，`language` 固定塞 `"plmysql"`，其余流程完全复用原生 `CreateFunction()` DDL 路径（`pg_proc` 写入、依赖跟踪、ACL）——不新增目录代码。

同时修复：
- `opt_definer` 接入例程产生式，落 `proowner`
- `COMMENT` 子句接入，落 `pg_description`
- `DETERMINISTIC` 改映射 `STABLE`（不再是 `IMMUTABLE`）

### 4.3 PL 引擎：`src/pl/plmysql/`

**决策：克隆 `src/pl/plpgsql/` 为 `src/pl/plmysql/`**（方案 B，非双方言共享方案）。

理由（详见对话记录，此处摘要）：
1. Babelfish 自己的 PLtsql 分化幅度证明双方言共享一份语法/执行文件不可持续（`pl_gram.y` 从 4147 行分化到 8382 行，且 Babelfish 额外拆出 `pl_exec-2.c`/`pl_comp-2.c` 隔离方言专属语句）
2. openHalo 的 `plpgsql` 有在役依赖——[`createTriggerFunc()`](../../../src/backend/parser/mysql/mys_parse_utilcmd.c:849) 在 MySQL 协议会话里生成 `LANGUAGE plpgsql` 触发器函数处理 `AUTO_INCREMENT`。若改造 `plpgsql` 本体做双方言分支，任何方言判断逻辑的 bug 都可能污染这条现有链路，风险面不可控
3. 与 openHalo 现有 house style 一致（`gram.y→mys_gram.y`、`utility.c→mys_utility.c`、`tablecmds.c→mys_tablecmds.c` 均为克隆改造），改动收敛在新目录内，不扩大与上游 PG 合并冲突的文件集合

**目录布局（克隆映射）**：

| 源（plpgsql） | 目标（plmysql） | 改造程度 |
|---|---|---|
| `pl_gram.y`（4147 行） | `pl_gram.y` | 大改——替换为 MySQL SQL/PSM 文法 |
| `pl_scanner.c` / `pl_reserved_kwlist.h` / `pl_unreserved_kwlist.h` | 同名 | 中改——MySQL 关键字表 |
| `pl_comp.c` | 同名 | 中改——编译期符号表需扩展（CONDITION、HANDLER 声明顺序校验） |
| `pl_exec.c` | 同名 | **尽量少改**——核心语句执行（IF/LOOP/赋值/SPI 调用）直接复用 |
| `pl_handler.c` | 同名 | 中改——`call_handler`/`validator`；`fn_is_trigger` 分支预留但不启用（§4.10） |
| `pl_funcs.c` | 同名 | 小改——语句节点打印/调试支持 |
| — | `pl_exec_ext.c`（新增，仿 Babelfish `pl_exec-2.c`） | 全新——MySQL 专属语句执行（HANDLER 注册、SIGNAL、游标 NOT FOUND 联动） |
| — | `pl_comp_ext.c`（新增） | 全新——HANDLER/CONDITION 编译期处理 |

**语义映射表**（MySQL SQL/PSM → plpgsql 内部节点，一一对应部分直接复用 `pl_exec.c` 执行逻辑）：

| MySQL SQL/PSM | plpgsql 节点 |
|---|---|
| `DECLARE v type DEFAULT expr` | `PLpgSQL_var` |
| `IF/ELSEIF/ELSE/END IF` | `PLpgSQL_stmt_if` |
| `CASE...END CASE` | `PLpgSQL_stmt_case` |
| `WHILE...END WHILE` | `PLpgSQL_stmt_while` |
| `LOOP...END LOOP` | `PLpgSQL_stmt_loop` |
| `REPEAT...UNTIL...END REPEAT` | `PLpgSQL_stmt_loop` + 尾部条件 exit |
| `LEAVE label` | `PLpgSQL_stmt_exit`(is_exit=true) |
| `ITERATE label` | `PLpgSQL_stmt_exit`(is_exit=false) |
| `DECLARE c CURSOR FOR ...` | `PLpgSQL_var`(refcursor) |
| `OPEN`/`FETCH INTO`/`CLOSE` | `PLpgSQL_stmt_open/fetch/close` |
| `SELECT...INTO` | `PLpgSQL_stmt_execsql`(into) |
| `RETURN expr` | `PLpgSQL_stmt_return` |

真正需要新写执行逻辑的只有 `DECLARE HANDLER`（§4.5）和 `SIGNAL`/`RESIGNAL`（§4.8）——两者都不是简单映射，是 plpgsql 原生没有的语义。

### 4.4 编译期符号表扩展

`pl_comp.c` 的符号表需要新增两类条目（plpgsql 原生没有）：

- **CONDITION**：`DECLARE cond CONDITION FOR {errno｜SQLSTATE 'x'}` 声明的具名条件，编译期解析为 `(SQLSTATE, 可选errno)` 二元组，供后续 `HANDLER`/`SIGNAL` 语句按名引用
- **HANDLER 声明顺序校验**：MySQL 要求 `DECLARE` 顺序严格为 变量/条件 → 游标 → 处理程序，违反顺序在 MySQL 是编译错误，`pl_comp_ext.c` 需要在符号表插入时做顺序检查

### 4.5 CONTINUE HANDLER：逐语句 savepoint + 错误分类

**这是全部工作里语义上最难的一块**，因为 plpgsql 的 `EXCEPTION WHEN` 是 EXIT 语义（块级子事务回滚，不可恢复到出错语句之后），而 MySQL `DECLARE CONTINUE HANDLER` 要求处理完 handler 后**从出错语句的下一条继续执行**。

参考 Babelfish 解决同构问题（T-SQL `XACT_ABORT OFF` 批处理的语句级续行）的模式（`iterative_exec.c:1160-1450`）：

- **仅对声明了 `CONTINUE HANDLER` 的块启用**（避免无条件性能代价）：编译期检测到块内有 CONTINUE 类型的 handler 时，把块内每条顶层语句单独包一层 `BeginInternalSubTransaction()`/`PG_TRY`
- 语句出错时，在 `PG_CATCH` 里将错误的 SQLSTATE 与块内声明的 handler 条件表逐一匹配：
  - 命中 CONTINUE handler → 回滚语句级子事务保存点，执行 handler 语句，继续下一条
  - 命中 EXIT handler → 回滚整个外层块的子事务，执行 handler，跳出块（复用 plpgsql 原生 `EXCEPTION` 路径）
  - 未命中 → 按 SQLSTATE 类前缀（`SQLWARNING`=01xxx / `NOT FOUND`=02xxx / `SQLEXCEPTION`=其余）二次匹配
  - 仍未命中 → 正常向外层抛出

EXIT handler 复用 plpgsql 原生 `EXCEPTION WHEN` 机制（零新增）；CONTINUE handler 是本设计唯一需要新建执行路径的部分。

**游标 NOT FOUND 联动**：plpgsql 的 `FETCH` 越界只置 `FOUND = false`，不抛异常，无法触发上述错误捕获路径。`pl_exec_ext.c` 的 FETCH 执行需要在 MySQL 方言下改为：越界时抛出可被 `NOT FOUND` 类 handler 捕获的条件（SQLSTATE `02000`），而不是静默置标志位。这是 MySQL 存储过程里最常见的写法（`DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;` 配合游标遍历），必须支持。

### 4.6 CALL 链路：OUT/INOUT 参数回写

不修改 `ExecuteCallStmt()`。复用其原生行为：过程有 OUT/INOUT 参数时，返回值本就打包成一行 `RECORD`（PG≥11 标准行为，openHalo 该函数未修改，`functioncmds.c:2207-2379`）。

新增的是"调用后"这一步——在 MySQL 协议的 CALL 结果处理路径（`mys_utility.c` 或 `adapter.c` 的 `CMDTAG_CALL` 分支）里：

1. 已有的 `stmt->outargs`（`mys_analyze.c:2205` 构建，元素为 `UserVarRef`）逐一对应 `RECORD` 结果行的各列
2. 对每个 `outarg`，调用已存在的 [`mysSetUserVarForPl(name, value, typeOid, isNull)`](../../../src/backend/commands/mysql/mys_uservar.c:142) 写回对应 `@变量`

工作量集中在"识别 CALL 语句何时需要走这条回写分支、如何从 `PortalRun` 结果里取出这行 RECORD"，不是重新设计回写机制——`mysSetUserVarForPl` 已经是 `SELECT...INTO @var` 在用的同一个函数（`mys_utility.c:1686`）。

### 4.7 多结果集协议打通

现状 `moreResultsFlag` 只在 [`postgres.c:1122-1140`](../../../src/backend/tcop/postgres.c) 顶层多语句循环里置位，`CALL` 内部执行是单次调用，走不到这段代码。

新增触发点（参考 Babelfish `pl_exec-2.c:735-776` 的 `exec_stmt_push_result` 模式）：

- 编译期：`plmysql` 编译器在遇到例程体内**未被 `INTO` 消费的顶层裸 `SELECT`** 时，标记为"推送结果集"语句（区别于普通 `PLpgSQL_stmt_execsql`）
- 执行期：该语句执行时不走 SPI 拿结果再丢弃，而是开一个真实 Portal，用 `DestRemote` 直接 `PortalRun` 把结果流式写到当前 MySQL 协议连接（与顶层 `SELECT` 走的是同一套发送路径）
- 每次推送前检查"后面是否还有更多推送型语句待执行"，据此设置/清除 `moreResultsFlag`，逻辑与现有顶层批处理判断（`stmtIndex < stmtsNum`）同构，只是判断粒度从"批内剩余语句数"变成"例程体内剩余推送型语句数"

### 4.8 错误码体系

**修复既有 3 类问题**（§2.6）：
- 3 条死条目（键值颠倒）直接删除重建
- 4 条错误映射订正：`42601`(语法错误)→1064，`22P02`→1366，`23514`→按场景（MySQL 5.7 无 CHECK 约束，实际很少触发，可映射到通用 1264 或删除该条），`P0001` 单独处理（见下）
- 兜底从"原样返回 PG 编码"改为 `1105 ER_UNKNOWN_ERROR`

**扇出问题**（参考 Babelfish `error_mapping.txt` 167 条的结构洞察）：单一 SQLSTATE 键会扇出到多个 MySQL errno（如 `42601` 语法错误在 MySQL 里按具体场景分 1064/1149/1583 等）。不需要对齐 MySQL 全部约 2000 个 errno，但需要把查找键从纯 SQLSTATE 扩展为 `(SQLSTATE, 消息模式)` 二元组，在现有哈希表基础上加一层消歧，覆盖存储过程常用条件（预估 40–60 条，非全量重建）。

**`SIGNAL`/`RESIGNAL` 专属通道**（阻塞点，见 §2.6）：`SIGNAL SQLSTATE 'xxxxx' SET MYSQL_ERRNO = n, MESSAGE_TEXT = '...'` 必须让显式指定的 `MYSQL_ERRNO` 直接穿透到错误包，**绕过** `convertErrorCode()` 查表。未显式指定时，`45000` 类默认 errno 为 `1644`(`ER_SIGNAL_EXCEPTION`)，不查表、不落到 `P0001→1264` 这条通用映射上。`RESIGNAL` 复用同一通道，允许在原条件基础上覆盖部分诊断项。

**反向映射**（新增，供 `DECLARE HANDLER FOR 1062` 使用）：MySQL errno → SQLSTATE 反向查找，需注意非单射（如现有映射里 `1264` 同时对应 `22003`/`23514`/`P0001` 三个 PG 源）——反向表需为每个 MySQL errno 选定一个规范 SQLSTATE，与正向表分开维护，不能简单反转哈希。

**`GET DIAGNOSTICS ... MYSQL_ERRNO`**：诊断区取值时复用正向映射表的查询逻辑，与发包时的查询是同一张表的两个调用点。

### 4.9 元数据层修正

保留视图路线（`mysql.proc`/`mys_informa_schema.procedures/functions/routines` 继续投影 `pg_proc`），不新建独立目录表。最终落地时没有采用 Babelfish 的窄侧表（`sys.babelfish_function_ext`）补充方案，而是用 **`pg_proc.proconfig` + 自定义 GUC**（`plmysql.definer`/`plmysql.sql_mode`/`plmysql.sql_data_access`/`plmysql.created`/`plmysql.last_altered`，由 plmysql 扩展注册）承载 `pg_proc` 存不下的列，理由：

- `proconfig` 随 `pg_proc` 行整体 dump/restore 与逻辑复制，无需在恢复路径上补写窄侧表（窄侧表的行在 `pg_restore`/逻辑复制重建例程后必然丢失或需要额外钩子）
- 函数级 GUC 在调用时由 fmgr 自动应用到会话，plmysql 编译器/执行器可以零成本读取快照（执行期 `plmysql.sql_mode` 即创建时值，为 §G 的"创建时记录、执行时应用"铺路）
- 零新目录代码、零孤儿行清理责任（DROP 例程时随行删除）

已落地内容（2026-08-29 晚）：

- 语法层 `DEFINER=user@host` 原文与显式 SQL data-access 特性经选项 `SET` 子句写入 `proconfig`；`mys_utility.c` 在执行期按会话 `sql_mode` 与当前时间追加 `sql_mode`/`created`/`last_altered`，避免在 PREPARE 解析期快照到错误值
- `mysql.proc`/`mys_informa_schema.{procedures,functions,routines}` 与 `SHOW CREATE` 读取 `proconfig` 展示真实 definer/sql_mode/SQL data access/时间戳；无记录时（如旧版本重建的例程）回退到原展示值（owner@%、默认 sql_mode、`CONTAINS SQL`、`2024-1-1`）
- `mysql.get_proc_def()`/`get_func_def()` 直接输出 `prosrc`（本来存的就是原文），并在头部渲染记录的 DEFINER 与 SQL data access
- 仍保持 `ROUTINE_BODY`/`language = 'SQL'`：这是 MySQL 5.7 的协议值，内部 `prolang = plmysql` 不应泄露

### 4.10 触发器：MySQL 行级 DML 子集

M7 已实现 MySQL 5.7 的基本 `CREATE TRIGGER`：

```sql
CREATE [DEFINER = user] TRIGGER name
  BEFORE | AFTER INSERT | UPDATE | DELETE ON table
  FOR EACH ROW trigger_body
```

`trigger_body` 可以是一条语句（末尾分号可省）或裸 `BEGIN ... END` 块。`mys_gram.y` 原样捕获该体，utility 层先建立私有的 `plmysql RETURNS trigger` 函数，再调用 PG 原生 `CreateTrigger()`；包装体自动追加 `RETURN NEW`（BEFORE INSERT/UPDATE）、`RETURN OLD`（BEFORE DELETE）或 `RETURN NULL`（AFTER）。因此 PG 负责调度，`plmysql` 已有的 `NEW`/`OLD` 编译与执行路径负责语义。

原始 MySQL 体、名称和 DEFINER 保存为函数级 GUC（`plmysql.trigger_body`/`plmysql.trigger_name`/`plmysql.definer`）；aux_mysql 1.9 的 `mys_informa_schema.triggers` 与 `SHOW CREATE TRIGGER` 读取这些值，避免把内部 `RETURN` 包装泄露给客户端。私有函数使用受保留前缀的 `CREATE OR REPLACE`，故删表后同名触发器可以重建。

MySQL 专用的 `DROP TRIGGER [IF EXISTS] [schema.]name`（无 ON 子句，名字是 schema 级作用域）也已支持（2026-08-30）：解析器用私有前导名 `__mysql_drop_trigger__` 标记该形态，utility 层在 `RemoveObjects()` 之前解析出所属表并把对象改写为 PG 标准的 `[表名…, 触发器名]` 形态，之后走完全原生的删除路径。解析规则：先找 MySQL `CREATE TRIGGER` 生成的私有函数 `__mysql_trigger_<名>` 所对应的触发器；否则在目标 schema（限定名指定，未限定名取 search_path 首个 schema，对应 MySQL 的当前数据库）内找同名且唯一的触发器（兼容原生 PG 触发器）；同名多表歧义时报错并提示改用 PG 语法。触发器不存在时按 MySQL 语义报 1360（`ER_TRG_DOES_NOT_EXIST`，经 pending-errno 通道穿透，不污染全局 SQLSTATE 映射表），`IF EXISTS` 则发 NOTICE 跳过。与 CREATE 侧一致，显式 DROP TRIGGER 后私有函数保留，同名触发器可直接重建。另补 schema 级唯一性检查（2026-08-30）：MySQL 触发器名在 schema 内唯一，`CREATE TRIGGER` 时若同名触发器已存在于该 schema 的任意表上（含原生 PG 触发器），按 MySQL 报 1359（`ER_TRG_ALREADY_EXISTS`，pending-errno 通道）；`DROP TABLE` 与被 `DROP TRIGGER` 移除后名字可复用。

刻意不支持：多事件、`TRUNCATE`、`INSTEAD OF`、语句级触发器以及 `FOLLOWS`/`PRECEDES` 顺序；这些不应静默降级为 PG 语义。

---

## 5. Babelfish 对照与技术取舍

Babelfish（AWS 的 SQL Server 兼容层）验证了"clone plpgsql 建新 PL"是生产级可行路线——PLtsql 就是这么起家的。以下是可直接移植/不移植的技术判断：

### 采纳

| 技术 | Babelfish 出处 | 本设计应用 |
|---|---|---|
| 过程体原文截取产生式 | `gram-tsql-rule.y:4145-4187` `tokens_remaining` | §4.2 |
| OUT 参数：调用前组装目标行、复用原生 CALL 返回的 RECORD、调用后灌回变量 | `pl_exec-2.c:1032-1156` + `exec_move_row()` | §4.6 |
| 多结果集：编译期标记裸 SELECT，执行期 DestRemote 直送 | `pl_exec-2.c:735-776` `exec_stmt_push_result` | §4.7 |
| 语句级 savepoint + 错误分类 + 继续下一条 | `iterative_exec.c:1160-1450` | §4.5（CONTINUE HANDLER） |
| 错误映射键需要消歧维度，不能只用 SQLSTATE | `error_mapping.txt`（167 条，`(SQLSTATE,消息模式,关键字)` 三元组） | §4.8 |
| 元数据：原生目录为准 + 窄侧表补充 | `sys.babelfish_function_ext` | §4.9 |

### 明确不采纳

| 技术 | 不采纳原因 |
|---|---|
| 字节码/GOTO 执行引擎（`codegen.c`/`iterative_exec.c` 的 `DynaVec`+程序计数器） | 解决的是 T-SQL 裸 `GOTO` 的问题；MySQL SQL/PSM 只有结构化 `LOOP`/`WHILE`/`LEAVE`/`ITERATE`，树形解释器（plpgsql 原生执行模型）完全够用，引入字节码引擎是不必要的复杂度 |
| `find_rendezvous_variable` 跨 `.so` 握手 + `PLtsql_protocol_plugin` 60+ 函数指针结构体 | 解决的是 Babelfish"扩展优先、内核只加最小 hook"打包策略下跨动态库边界通信的问题。openHalo 直接改内核源码，`ParserRoutine` 本来就长在 core 里，没有跨 `.so` 边界，这层间接完全不需要 |
| ANTLR 前端 | Babelfish 用 ANTLR 是因为 T-SQL 文法复杂度和已有 grammar 资产；openHalo 全仓统一用 bison/flex（`mys_gram.y`/`mys_scan.l`），MySQL SQL/PSM 文法复杂度远低于 T-SQL，沿用 bison 保持工具链一致性 |

---

## 6. 分期计划

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | 语法层过程体捕获（§4.2）+ `src/pl/plmysql/` 骨架（克隆改名，`DECLARE`/赋值/`IF`/`RETURN` 可跑） | ✅ 完成 |
| M2 | 完整流程控制（`LOOP`/`WHILE`/`REPEAT`/`LEAVE`/`ITERATE`/`CASE`）+ 局部变量完整语义 | ✅ 完成 |
| M3 | 游标（`DECLARE CURSOR`/`OPEN`/`FETCH`/`CLOSE`）+ EXIT HANDLER（复用 plpgsql EXCEPTION） | ✅ 完成 |
| M4 | CONTINUE HANDLER（§4.5，含游标 NOT FOUND 联动）+ `SIGNAL`/`RESIGNAL`（§4.8）+ `GET DIAGNOSTICS` | ✅ 完成；错误码体系（§4.8）三项均已落地：正向表已扩至 53 条生效条目（`errorConvertor.c`：11 条 openHalo 专有编码 + 20 条存储过程常用 `ERRCODE_*` + 22 条更广 DDL/DML/routine 映射；另有 15 条历史失效条目已注释保留、不计入生效范围），errno→SQLSTATE 双向/规范性反向映射在 `pl_exec_ext.c` 的 `mysql_errno_sqlstate_map`（27 条三元组：errno/PG SQLSTATE/MySQL 规范 SQLSTATE） |
| M5 | CALL 链路 OUT/INOUT 回写（§4.6）+ 多结果集协议打通（§4.7） | ✅ 完成（多结果集协议打通是 2026-08-29 补的：编译期 `is_select`/`n_resultsets` 标记早就有，执行期一直没接上，`CALL` 内裸 `SELECT`/`EXECUTE` 预处理语句会报 "no destination for result data"；另外例程体内 `SET @uservar = expr` 与 MySQL 形态的 `EXECUTE stmtname [USING ...]` 当时也还不能用，一并修了） |
| M6 | 元数据视图修正（§4.9）+ `DEFINER`/`COMMENT` 语法补全 + 触发器预留验证（§4.10，不实现触发器本身） | ✅ 完成：`DEFINER` 的 `user@host` 原文、创建时 `sql_mode` 快照、SQL data-access 特性、`created`/`last_altered` 时间戳以函数级 GUC 形式写入 `pg_proc.proconfig`（`plmysql.definer`/`plmysql.sql_mode`/`plmysql.sql_data_access`/`plmysql.created`/`plmysql.last_altered`，由 plmysql 扩展定义并随 dump/restore 自动携带），`mysql.proc`/`mys_informa_schema.routines/procedures/functions` 视图与 `SHOW CREATE` 全部改读真实值（SQL data access 缺省时回退为 `CONTAINS SQL`）；触发器入口预留已验证：三态枚举、编译器 switch、`plmysql_exec_trigger`/`plmysql_exec_event_trigger` 执行器、调用分派与语法 guard（如 1336 动态 SQL 拒绝）均就位 |
| M7 | MySQL `CREATE TRIGGER` 行级 DML 子集 + 原始体元数据/`SHOW CREATE TRIGGER` | ✅ 完成（2026-08-30）：单语句与 `BEGIN...END` 体降级到私有 `plmysql RETURNS trigger` 包装函数；支持 DEFINER、`NEW`/`OLD`、BEFORE/AFTER 单事件，以及删表后的同名重建；MySQL 专用 `DROP TRIGGER [IF EXISTS] [schema.]name` 同日补齐（见 §4.10）；aux_mysql 升至 1.9 |
| M8（clone 残留清理） | `plmysql` 语法层的 plpgsql 残留收口：整数/游标/查询 `FOR` 循环、`FOREACH..IN ARRAY`、`MOVE`、可滚动游标方向（`PRIOR`/`FIRST`/`LAST`/`ABSOLUTE`/`RELATIVE`/`FORWARD`/`BACKWARD`/`ALL`/`SCROLL`）、plpgsql 专属 `GET DIAGNOSTICS` 项（`PG_CONTEXT`/`PG_EXCEPTION_*`/`PG_DATATYPE_NAME`）、plpgsql 风格块级 `EXCEPTION WHEN...THEN`——这些均非 MySQL 语法，此前被静默接受，现在一律语法报错；对应的执行器/dump 死代码一并删除 | ✅ 完成（2026-08-30）：删除的产生式/token 与关联 C 代码见 `pl_gram.y`/`pl_exec.c`/`pl_funcs.c`/`plmysql.h` diff；`FOREACH`/`MOVE` 特意保留为无产生式的保留关键字（不能降级成 unreserved，否则会被 `stmt_execsql` 的 `T_WORD` 兜底通道当成任意 SQL 直接透传给 SPI——`MOVE` 恰好还是合法的 PG 原生游标语句，之前一度静默编译通过而不报错，已验证修正）；`NULL;` 空语句保留未删——它虽然也不是 MySQL 语法，但是纯无操作、不存在与 MySQL 语义冲突的风险，且 `plmysql` 自身测试套件把它当占位符广泛使用，成本收益不对称，故意排除在收口范围外；顺带发现 `COMMIT`/`ROLLBACK` 其实是合法但此前从未验证过的 MySQL 存储过程语法（`SQL SECURITY` 语义不同，不应被当残留删掉），补齐了 FUNCTION/TRIGGER 内的 1422 `ER_COMMIT_NOT_ALLOWED_IN_SF_OR_TRG` 校验（见 §7 风险 6 的运行时缺口）；新增 `test_021_plpgsql_residue_removed.py` |

**2026-08-29 追加修复**（运行时正确性问题，不改变上述里程碑范围）：
- `DECLARE` 声明顺序校验（§E）此前对变量、游标声明完全不生效，且 HANDLER 动作体若自身是嵌套块会清空外层块的顺序/HANDLER 收集状态——已改为保存/恢复栈
- `SIGNAL` 的自定义 SQLSTATE 发包时被硬编码替换为 `"HY000"`，客户端拿不到真实值——已改为发送真实 SQLSTATE（`adapter.c`）
- `max_sp_recursion_depth` 的 0–255 会话范围、过程递归上限（1456）、函数递归禁止（1424）、函数结果集禁止（1415）均已补齐
- 函数/触发器内的 MySQL 命名预处理语句已在编译期以 1336 拒绝；`plmysql` HANDLER 动作列表的语义类型与两个遗漏的枚举分支也已修正

---

## 7. 风险与未决项

1. **CONTINUE HANDLER 性能代价**：逐语句 savepoint 有开销，需要实测大循环内 CONTINUE HANDLER 的性能表现，评估是否需要"仅对可能触发对应条件的语句包裹"的静态分析优化（Babelfish 论文/注释提到过这个方向但未确认其是否真正实现，需要在 M4 阶段针对 openHalo 场景单独验证）。
2. **`SET` 语句歧义**：MySQL 模式下 `SET` 已被系统变量/用户变量语法占用，例程内 `SET localvar = expr` 需要与现有 `MysVariableSetStmt` 语法在 `plmysql` 编译器内部（不是主语法）做区分，具体消歧规则需要在 M1 实现时敲定。
3. **原生 `label:` 拼写**：✅ 已支持（2026-08-29 晚）。实现要点：plmysql 语句以 `T_WORD` 开头时（`SELECT` 等经 `stmt_execsql` 的 T_WORD 分支捕获整句），不能在 bison 里用 `T_WORD ':'` 双 token 产生式区分 label——bison 需要两 token 前瞻，而 pl_scanner 的动作内 `yylex()` 与 bison 的 lookahead 缓冲错位，会导致所有 T_WORD 开头的语句解析错乱（`SELECT CASE WHEN...` 报 `missing "WHEN"`）。正确做法是把 `标识符 + ':'` 在 scanner 层合并为单一 `T_WORD_COLON` token（`pl_scanner.c`），与 `A.B`/`A:=`/`A[B]` 的既有组合机制同构；label 只接受普通标识符（`T_WORD`），不接受关键字/引号标识符，符合 MySQL 语义。
4. **反向错误码表的规范化选择**：非单射的反向映射（如多个 SQLSTATE 对应同一 MySQL errno）需要逐条人工选定规范源，M4 阶段需要一份人工审核的映射表，不能全自动生成。✅ 已按 MySQL 5.7 手册附录逐条人工选定（`pl_exec_ext.c` 的 27 条三元组）。
5. **`sql_mode` 快照的实际使用范围**：快照已落地存储（`plmysql.sql_mode` proconfig GUC），并在例程进入时映射到适配器的运行时 mode 位；空字符串也是有效快照，嵌套例程和 ERROR 展开均恢复调用者状态。现有 `STRICT_TRANS_TABLES`/`STRICT_ALL_TABLES` 数值转换路径已由该状态驱动。

   **扫描/解析期 mode（2026-08-30 追加）**：`ANSI_QUOTES`、`NO_BACKSLASH_ESCAPES`、`PIPES_AS_CONCAT` 三项已在 `mys_scan.l`/`mys_gram.y` 接入 `mys_sqlMode` 位，覆盖 `test_022_sql_mode_scan_parse.py`：
   - `ANSI_QUOTES`：`mys_scan.l` 新增 `<xd>` 排他状态（此前只在头注释里提过、从未真正声明/实现），`"..."` 打开时走分隔标识符（镜像 `` `...` `` 的实现），关掉时走原来的 `<xde>` 字符串状态；两者共享同一套开/闭引号词法，`{xdqstart}` 的动作按位分流。
   - `NO_BACKSLASH_ESCAPES`：单引号/双引号字符串各自本来就有一对闲置状态——`<xq>`（无转义）和 `<xe>`（有转义，此前 `{xqstart}` 硬编码只进 `<xe>`）、`<xdq>`/`<xde>` 同理——两边的闭引号/加倍引号/EOF 规则本来就是共享的，缺的只是入口分流，不需要新写状态机。
   - `PIPES_AS_CONCAT`：`&&`/`||` 符号此前一直无条件编译成 aux_mysql 的 `mysql.&&`/`mysql.||` 自定义算子族（一批按操作数类型重载、把两侧强转真值再做布尔运算、结果是 MySQL 风格整数 0/1 的函数）——这本身是对的，`&&` 保持不变；只有 `Op_Or` 需要在 `PIPES_AS_CONCAT` 打开时改道：显式限定到 `pg_catalog.||` 并把两侧显式转 `text`（绕开 `mysql.||` 更宽的 `anynonarray` 重载，同时让 `1 || 2` 之类纯数字操作数也能按 MySQL CONCAT 语义拼成 `'12'`，NULL 传播行为不变）。
   - `REAL_AS_FLOAT` **未做**：现状是 `REAL` 类型固定映射到 `mysql.real`（`aux_mysql--1.1.sql` 里建的、包在 `float8` 上的 DOMAIN），要让它在 `REAL_AS_FLOAT` 打开时改成 4 字节精度，需要新增一个包在 `float4` 上的 `mysql.float`-风格 DOMAIN 并让 `mys_gram.y` 的 `REAL` 产生式按位选择——这是 aux_mysql 扩展的 schema 变更（新对象、版本号升级、升级脚本），跟另外三项纯扫描器/语法层改动性质不同，没有一并做，留作后续任务。
   - 完整 MySQL DML 截断告警语义（每条 INSERT/UPDATE 列值溢出/截断时的 warning-vs-error 行为）同样未做，是比这四个 mode 位更大的独立特性，不在本次范围。
6. **MySQL 协议 `CALL` 未走非原子执行路径**（M8 清理途中发现，非本次改动引入）：`COMMIT`/`ROLLBACK` 语句本身在 `PROCEDURE` 里编译、执行器代码（`exec_stmt_commit`/`exec_stmt_rollback`，真调用 `SPI_commit()`/`SPI_commit_and_chain()`）都在，但实际 `CALL` 时报 PG 层 1105 `invalid transaction termination`：`pl_handler.c` 的 `nonatomic` 判定要求 `fcinfo->context` 是带 `atomic=false` 的 `CallContext`（PG 标准 `CallStmt` 执行路径的产物），而 MySQL 协议自己的 `CALL` 分发目前不构造这个 `CallContext`，`fcinfo->context` 恒为 NULL，于是恒被当成 atomic 会话执行。修复需要改 MySQL 协议适配层的 `CALL` 分发（不是 `plmysql` 语法/编译层的事），不在本次语法清理范围内，留作后续任务；`test_021_plpgsql_residue_removed.py` 只钉住"编译得过"，没有断言 `CALL` 执行成功。
7. **DEFINER 用户名不改变 `pg_proc` 属主**（2026-08-30 讨论后有意保留的范围）：`DEFINER='user'@'host'` 目前只写入 `plmysql.definer` proconfig GUC 供 `SHOW CREATE`/`mysql.proc`/`information_schema` 展示，例程实际执行时的身份/权限仍由 `pg_proc` 的真实属主（即创建者）决定，不会因为 `DEFINER` 具名了另一个用户而改变。要让 `SECURITY DEFINER` 真正"以 DEFINER 用户的权限运行"，最小可行方案是：CREATE 时若 DEFINER 用户名能匹配到一个已存在的 PG 角色，就对该函数执行等价于 `ALTER FUNCTION ... OWNER TO` 的属主变更，完全复用 PG 原生的属主变更权限检查（必须是超级用户或目标角色成员），不新写权限判断逻辑；创建者无权限把属主改成目标角色时应直接报错（对齐真实 MySQL 要求 SUPER/SET_USER_ID 权限才能指定别人为 DEFINER）。已就此方案与用户确认，本次**有意不做**，留作独立的后续任务（涉及权限模型变更，需要更谨慎的单独评审）。已经修的是一个更小、无权限含义的相邻缺口：`SQL SECURITY` 子句缺省时的默认值本身（PG 原生默认 INVOKER，MySQL 5.7 默认 DEFINER）——见 §3.A 与 `test_023_sql_security_default.py`。

---

## 8. 测试策略

现状：MySQL 协议回归位于 `src/test/mysql/t/test_000` 至 `test_023`，覆盖过程体、流程控制、游标/HANDLER、OUT/INOUT、多结果集、动态 SQL、扩展升级、dump/restore、例程特性、递归/函数限制、元数据（DEFINER/sql_mode 快照/SQL data access/时间戳/`SHOW CREATE`，含 `ALTER PROCEDURE` 响应）、原生 `label:` 与错误码映射（含发包 SQLSTATE 规范化断言）、CREATE TRIGGER 的复合/单语句体、`NEW`/`OLD`、DEFINER、元数据还原和同名重建、MySQL 触发器唯一的 1359，DROP TRIGGER 的 MySQL/PG 双拼写、IF EXISTS、1360 错误、删表后的孤儿名字和同名触发器优先级，mysqldump 格式黑盒导入（可执行注释、DELIMITER 切分、NOT VALID 外键，`test_019_mysqldump_import.py`），sql_mode 快照的执行期语义（`test_020_sql_mode_semantics.py`：嵌套 CALL、ERROR 清理），plmysql 语法层 plpgsql 残留收口（`test_021_plpgsql_residue_removed.py`：见 M8）与 sql_mode 扫描/解析期语义（`test_022_sql_mode_scan_parse.py`：`ANSI_QUOTES`/`NO_BACKSLASH_ESCAPES`/`PIPES_AS_CONCAT`，见 §7 风险 5），以及 `SQL SECURITY` 缺省默认值（`test_023_sql_security_default.py`：见 §7 风险 7）；`PYTHONPATH=/home/unvdb/pylibs make -C src/test/mysql check` 当前为 **24/24 通过**。

后续需补充：

- 语法覆盖：对标矩阵（§3）里每个 ✅ 目标项至少一条用例
- CALL 链路：OUT/INOUT 单参数、多参数、混合 IN/OUT、@变量复用同名场景
- 多结果集：单 SELECT、多 SELECT、SELECT+INTO 混合场景下的客户端可见结果集数量
- CONTINUE HANDLER + 游标：标准的"遍历游标直到 NOT FOUND"写法必须覆盖，这是 MySQL 存储过程里最高频的模式
- 错误码：修复的 4 条错误映射 + 3 条死条目补全后的正确性，`SIGNAL` 带/不带 `MYSQL_ERRNO` 两种场景
- 跨协议边界：psql 协议调用 `plmysql` 例程应报错；`pg_dump`/还原链路下创建应成功
- mysqldump 导入回归：`tools/convert_mysqldump_file.py` 转换后的触发器/过程体可以作为黑盒用例，覆盖真实 dump 的 DELIMITER、注释和 DEFINER 形态
- `sql_mode`：严格/非严格快照、空快照与嵌套例程恢复（`test_020_sql_mode_semantics.py`）

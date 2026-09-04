# Procedure/Function 兼容功能补完研发方案(2026-09-05)

> 回答的问题:**procedure/function 的兼容功能当前还缺什么、能否补完?**
> 结论:**能。编译率口径预估 81.75% → ~95%(所有桶全做的理论上限);真正的
> 新开发集中在四件事——1304 剪依赖、体内事务语句族(START TRANSACTION /
> SAVEPOINT)、括号 SELECT 语句体、1691 错误码;其余是共享项(触发器/
> beyond-SP 方案已覆盖)和零开发的重测/文档修正。**

## 0. 基线

- 编译通过率 **81.75%(412/504)**(proc+func 合计,2026-09-05);
- 已收口(有回归):CREATE/DROP 全语法形态(单语句体/带标签体/RETURN expr)、
  DECLARE 变量/条件/handler/游标、流程控制、CALL 多结果集协议(C1+挂起修复)、
  OUT/INOUT 回写、C2 事务控制(definer 身份切换)、递归 1424/1456、
  1327/1193/1336/1415 错误码、sql_mode 快照、体内 SET 系统变量消歧(A4,
  test_027)、体内双引号字符串(A3)、mysqldump 直通、SHOW/元数据显示主体。

## 1. 缺口清单(逐项核实,标注归属)

### 1.1 编译正向(计入 412/504 的失败)

| # | 缺口 | 证据 | 语料 | 归属 |
|---|---|---|---|---|
| C1 | 1304 视图依赖阻塞 DROP FUNCTION/PROCEDURE | RemoveObjects→reportDependentObjects,2BP000 且无错误码映射 | **+30** | beyond-SP §2.F(方案已定) |
| C2 | FLUSH 语句族 | mys_gram.y 零 token | +14 | beyond-SP §2.A |
| C3 | 长 DEFINER 主机名 | 词法 63 字节截断 | +4 | 触发器方案 T1(共享) |
| C4 | **括号 SELECT 作为语句体** `(SELECT..) UNION (SELECT..)` | plmysql `stmt_execsql`(pl_gram.y:1862)只有 4 种起手,无 `(`;**另有隐患**:`is_select`(:2812)只认首词 select,不补则结果集不推送 | +3 | **本方案 PF1** |
| C5 | CHECKSUM/REPAIR/OPTIMIZE TABLE | 无 token | +5-8 | beyond-SP §2.C |
| C6 | ANALYZE/TRUNCATE/RESET 顶层已有,例程体 leader 未收 | mys_gram.y:12050 leader 列表 | +3-4 | **本方案 PF2(极小)** |
| C7 | ENUM/SET 作 DECLARE/RETURNS 类型 | 无类型域,1091 | +6 | beyond-SP §2.E |
| C8 | `/*!50003` 版本门控注释 | **疑已实现**(mys_scan.l:525-558 + test_019),文档归类过时 | +3(重测回收) | 零开发 |

### 1.2 运行期事务语句族(**procedure 独有的实缺口,此前文档未记录**)

| # | 缺口 | 证据 | 语料 |
|---|---|---|---|
| C9 | **体内 START TRANSACTION** | 现报 1235(SPI 拒绝 TransactionStmt;test_034 钉住) | sp_trans 内 3 处 |
| C10 | **体内 SAVEPOINT / ROLLBACK TO / RELEASE SAVEPOINT** | plmysql 文法与执行层**零支持**(pl_gram.y/pl_exec.c 均 0 命中;顶层 SAVEPOINT 语法已有,PG 直通);体内走 SPI 一律 1235 | **sp_trans 38 处**(含 BUG#13825 专项用例) |
| C11 | MySQL 的 savepoint-level 语义(函数/触发器执行前后隐式建/销一层 savepoint;过程默认与调用方同层) | 语料注释明示该语义(sp_trans.test 头部) | 13825 用例族 |

### 1.3 负向错误码(proc/function 侧)

| # | 缺口 | 证据 | 语料 | 归属 |
|---|---|---|---|---|
| C12 | 1691 LIMIT 处 SP 变量类型错误 | 无任何类型校验(LIMIT 非独立 token,变量成 Param) | **+6** | **本方案 PF3** |
| C13 | 1422 隐式提交 DDL | 只拦字面 COMMIT/ROLLBACK | +4 | 触发器方案 T6(共享) |
| C14 | 1442 修改正被使用的表 | 无追踪 | +3 | 触发器方案 T7(共享) |
| C15 | 1313 RETURN 在 PROCEDURE 体 | 同触发器根因 | +1-2 | 触发器方案 T5(共享) |
| C16 | 1054 未知列部分退化为 1064 | 随编译率改善连带 | 少量 | 无独立开发 |

### 1.4 显示层/杂项

- **C17** SHOW CREATE PROCEDURE/FUNCTION 不输出 SQL SECURITY 子句、
  information_schema 的 Security_type 硬编码 'DEFINER'(C2 改造遗留;
  显式 INVOKER 例程显示不准)——读 label 的 `plmysql.sql_security` 即可,
  随 aux_mysql 下次版本升级;**0.5-1 天**。
- **C18** 差距分析文档两处归类过时:A4(已修,test_027)、版本门控注释
  (疑已修)——零开发,随本方案提交修正。
- **C19** 1137(临时表不可重开)**建议永不实现**:PG 本无此限制,人为报错
  是反向兼容。

## 2. 逐项方案

### PF1 括号 SELECT 语句体(0.5-1 天,语料 +3)

`stmt_execsql` 加 `'('` 备选,同样进 `make_execsql_stmt`(其 paren_depth
追踪已具备,pl_gram.y:2746);两个注意点:①文法当前 `%expect 0`
(pl_gram.y:142),`(` 不在任何 proc_stmt 备选的 FIRST 集,预计无新冲突,
但需重验;②**必须同时扩 `is_select` 识别**(:2812-2826,跳过前导括号找
select)——否则语句能编译但结果集不计入 n_resultsets、不推客户端,破坏
上轮修好的 CALL 多结果集不变式。

### PF2 leader 三连(数小时,语料 +3-4)

ANALYZE/TRUNCATE/RESET 三个词已是关键词,各加一行进
`mysql_single_stmt_body_leader`(mys_gram.y:12050),复用"扫到分号"捕获。

### PF3 1691 LIMIT 变量类型(1 天,语料 +6)

精确挂点已定位:`exec_prepare_plan`(pl_exec.c:4091)`SPI_prepare_extended`
之后遍历 plan sources 的 `query->limitCount/limitOffset`(先例:
exec_simple_check_plan 触过这俩字段,pl_exec.c:7852),找 Param 节点按
`paramid-1` 映射回 datum,声明的变量类型非整型族即
`mysSetPendingMySQLErrno(1691)` + MySQL 文案。纯负向校验,无语义风险。

### PF4 体内 START TRANSACTION(1-2 天)

语义映射:MySQL 的 START TRANSACTION = **隐式提交当前事务 + 开新事务**。
PG 非原子过程里恰好有等价物 `COMMIT AND CHAIN`。翻译规则:在事务块内 →
`COMMIT AND CHAIN`;不在事务块内 → no-op(下一条语句隐式开新事务)。
修饰符(READ ONLY/READ WRITE/隔离级别/WITH CONSISTENT SNAPSHOT)一期
接受并忽略,文档化。插点:plmysql 编译期把体内首词 START TRANSACTION 的
语句标记,执行期走专用 exec(仿 exec_stmt_commit,pl_exec.c:4866)。
**注意**:test_034 的 1235 钉住块需翻转。

### PF5 体内 SAVEPOINT 族(3-5 天,L1;L2 单列)

**L1 显式命名 savepoint**(核心):
- SAVEPOINT name → `BeginInternalSubTransaction()` + 名字入本调用帧的
  savepoint 栈(xact.c 的内部子事务无名,但严格 LIFO,与 MySQL 命名
  savepoint 的可见性规则一致:同名新建、ROLLBACK TO 弹到该点、RELEASE 只删不回滚);
- ROLLBACK TO name → 依次 `AbortCurrentSubTransaction()` 弹栈至该名字;
- RELEASE name → `ReleaseCurrentSubTransaction()` 弹栈至该名字;
- 机制全部有现成先例:plpgsql 的 EXCEPTION 块就是 BeginInternalSubTransaction
  / Abort / Release 三件套(pl_exec.c 错误处理),等价于把 MySQL 的显式
  savepoint 映射到 PG 的内部子事务栈。
- **语义冲突点需处理**:PG 禁止子事务内 COMMIT(_SPI_commit 的
  IsSubTransaction 检查)——MySQL 的 COMMIT 会释放全部 savepoint。映射:
  体内 COMMIT 前若 savepoint 栈非空,先全部 Release 再 COMMIT(行为与
  MySQL "COMMIT 隐式释放所有 savepoint"一致)。
- **L2 savepoint-level 语义**(函数/触发器边界隐式层,13825 用例):更深的
  边界语义,建议随 L1 落地后按 13825 用例实测差距再决定是否补,单列评审。

### PF6 共享项引用(不重复设计)

1304(beyond-SP §2.F,~1 天,+30)、FLUSH 一期(§2.A,0.5-1 天,+14)、
维护语句(§2.C,1-2 天,+5-8)、ENUM/SET 一期(§2.E,1-2 周,+6)、
长 DEFINER(触发器 T1,0.5-1 天,+4)、1313(T5)、1422(T6)、1442(T7)。

### PF7 验证项(各 0.5 天,预计零/小开发)

- 触发器体内 CALL 过程(MySQL 允许;exec_stmt_call 已存在,补 e2e 回归
  钉行为即可);
- ALTER PROCEDURE/FUNCTION 特性面(MySQL 5.7 只允许 COMMENT/SQL DATA
  ACCESS 类,确认现状不误收)。

## 3. 排序与总量

| 序 | 项 | 量级 | 编译率爬坡(累计) |
|---|---|---|---|
| 0 | 回放工具重建(三方案共用) | 1-2 天 | 校准 C8 归类 |
| 1 | PF2 leader 三连 + C8 重测 | 数小时 | ~82.5%(+3-7) |
| 2 | PF1 括号 SELECT | 0.5-1 天 | ~83% |
| 3 | 1304(设计已定) | ~1 天 | **~89%(+30)** |
| 4 | FLUSH 一期 | 0.5-1 天 | ~92%(+14) |
| 5 | PF3 1691 + T5 1313 + T6 1422 | 2-3 天 | 负向 ~11 条 |
| 6 | 维护语句 + 长 DEFINER | 2 天 | ~94%(+9-12) |
| 7 | PF4 START TRANSACTION | 1-2 天 | 执行重放 +3 |
| 8 | **PF5 SAVEPOINT L1** | 3-5 天 | 执行重放 +38 处(最大单项) |
| 9 | ENUM/SET 一期 | 1-2 周 | **~95%(+6)** |
| 10 | C17 显示 polish / PF7 验证项 | 1-2 天 | — |

proc/function **独有**开发量:约 **9-14 天**(PF1-PF5+PF7+C17);
加共享项后全量到 ~95% 编译率与大幅改善的执行重放通过率。

## 4. 风险与边界

- **PF5 是本方案的核心风险项**:内部子事务栈与现有 handler(SQLEXCEPTION
  块本身也用子事务)叠加时,弹栈次序必须严格配平——设计上 savepoint 栈
  按调用帧隔离,handler 子事务独立计数,不共用一个栈;COMMIT 前弹空
  savepoint 的时机要过 13825 用例族;
- PF4 的 COMMIT AND CHAIN 与 definer 身份切换(本轮 C2)叠加:CHAIN 后
  新事务的 uid 快照=definer(xact.c prevUser 语义),预期正确,需加回归;
- PF1 的 is_select 不补会造成"能编译但结果集吞掉"的静默错误,务必同改;
- C19(1137)明确不做;C11(L2)单列评审,不捆在 L1 里。

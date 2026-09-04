# openHalo MySQL 兼容:SP 之外的功能设计(2026-09-05)

## 0. 背景与边界

SP(存储过程/函数/触发器)主体已收口:M1–M7 全部完成、两轮编译率冲刺至
81.75%(412/504,proc+func;触发器 92%)、C2 规则 2(definer 身份切换)已修、
回归 37/37(见 `2026-09-03-mysql-sp-compat-gap-analysis.md` §7 与 §3 C2 行)。

结构性结论:**剩余缺口的大头已不再是"例程体语法",而是平台级能力**——语句类、
类型系统、对象生命周期、权限模型。SP 引擎只是它们的第一个消费者:FLUSH 语句
在例程体外的顶层同样不存在,ENUM 不进 DECLARE 也过不了列 DDL。本文是这些
beyond-SP 项的设计与排序,需求源两个:

1. **官方语料泛化**:sp/trigger/sp_trans 之外,语句类缺口在任何 MySQL 语料里都会撞到;
2. **真实世界负载**:mysqldump 导入(`tools/convert_mysqldump_file.py` 只做外键重排,
   `--master-data`/`--lock-all-tables`/`--flush-logs` 变体产生的 FLUSH 语句现在直接
   1064)、ORM/运维工具(维护语句)、迁移评估工具(类型系统)。

## 1. 能力地图(六簇)

| # | 簇 | 现状(已核实) | 真实触发场景 | 对 SP 编译率 |
|---|---|---|---|---|
| A | 会话/锁语句:FLUSH 全家族 | **连 token 都没有**(mys_gram.y 零出现) | mysqldump 特定选项、运维脚本 | ~14 条 |
| B | LOCK TABLES/UNLOCK TABLES 真语义 | 已降级为 no-op(set_system_session_variable) | dump 一致性保护、1100/1099 负向 | 负向 8 条 |
| C | 维护语句:CHECKSUM/REPAIR/OPTIMIZE | 缺(ANALYZE/TRUNCATE/RESET 顶层已有) | 运维工具、ORM | ~5-8 条 |
| D | HANDLER ... READ | 缺 | 低(高性能游标读,小众) | ~1-2 条 |
| E | ENUM/SET 类型 | 无类型域,列/DECLARE/RETURNS 均 1091 | **迁移库高频**(列类型),不止 SP 的 6 条 | 6 条 |
| F | 对象生命周期:1304 等 | DROP FUNCTION 被视图依赖阻塞(2BP000 且无错误码映射) | mysqldump 重建序、ORM 迁移 | ~30 条 |
| G | 权限/账户模型 | SUPER=superuser() 代理,mysql.* 授权表纯展示 | 多租户、最小权限部署 | 0(不语料化) |

A+C+E+F 合计理论可将编译率推向 **~88-89%**;B/D 是正确性/长尾,不影响该指标。

## 2. 分簇设计

### 2.A FLUSH(P0/P1,两期)

**语义分档**(按 MySQL 5.7 `FLUSH [NO_WRITE_TO_BINLOG|LOCAL] option`):

| 档 | 子句 | 语义决策 | 理由 |
|---|---|---|---|
| no-op OK | logs / privileges / status / hosts / user_resources / query cache / optimizer_costs / error/general/slow/binary/engine logs | 解析+返回 OK,不动任何状态 | openHalo 无对应缓存或由 PG 自管;FLUSH PRIVILEGES 因鉴权直读 pg_authid 实时生效,重载本来就是空操作 |
| 一期 no-op、二期真语义 | `TABLES [list]` | 一期 OK(与 LOCK TABLES no-op 同先例);二期评估 | 表缓存 openHalo 无直接对应 |
| 单列评审 | `TABLES WITH READ LOCK`(FTWRL) | 全局读锁,PG 无干净等价物 | 见 2.B 的跨事务持锁难题;短期文档化为限制或 advisory-lock 近似 |

**实现**:mys_gram.y 新增 FlushStmt(FLUSH 目前零出现,作 unreserved keyword
加入,冲突风险低但需过 `%expect 48` 验证);分发层 no-op。例程体内编译率
顺带受益(leader 列表 +1)。

**工作量**:一期(全部 no-op 档)0.5–1 天;FTWRL 单列。

### 2.B LOCK TABLES 真语义(P2,难点单列)

现状 no-op 意味着 dump 期间**无并发保护**(能导入,但不忠实)。真语义两层:

1. **锁获取映射**(直接):READ → `LOCK TABLE ... IN SHARE MODE`;WRITE →
   `LOCK TABLE ... IN ACCESS EXCLUSIVE MODE`(持锁会话自身仍可读写,语义近似)。
2. **会话锁模式**(PG 没有):MySQL 的 LOCK TABLES 之后本会话只能访问已锁表
   (否则 1100/1099),且**锁跨事务持续**直到 UNLOCK TABLES;PG 的表锁存活于
   事务内,autocommit 下每语句一事务、锁即取即释——**无法按 PG 原生机制维持**。

设计方案(二选一,需评审):
- (a) 会话级"锁声明簿记 + 显式事务挂锁":LOCK TABLES 时开启一个长事务持有
  真锁,UNLOCK 时提交;风险:占住事务槽、与 dump 内的隐式提交冲突(MySQL
  LOCK TABLES 本身就隐式提交,行为要对齐);
- (b) 簿记 + 访问 gate 不加真锁:1100 语义做对(会话内校验),跨会话保护
  不承诺——诚实但弱。

建议:**先 (b) 后 (a)**,把 1100/1099 负向做掉,跨会话保护作为已知限制文档化,
等有真实一致性问题反馈再上 (a)。

### 2.C 维护语句 CHECKSUM/REPAIR/OPTIMIZE(P1)

- 统一结果集形态:REPAIR/OPTIMIZE → `Table/Op/Msg_type/Msg_text`;CHECKSUM →
  `Table/Checksum`;
- OPTIMIZE → `VACUUM FULL`?(锁代价高)还是 `VACUUM`+回显 OK?——倾向 VACUUM
  并回显 status OK(InnoDB 的 OPTIMIZE 本来就是重建建议而非必须);
- REPAIR → PG 无碎片区,直接返回 `status/OK`(MySQL 对 InnoDB 也基本是
  "repair not supported"路径);
- CHECKSUM 一期返回自算校验(逐行 hash):**不承诺与 MySQL 字节级一致**
  (页格式不同),QUICK/EXTENDED 修饰符接受但忽略,文档化差异;
- 顺带:ANALYZE/TRUNCATE/RESET 加进 `mysql_single_stmt_body_leader`(各一行,
  数小时,语料 +3-4)。

### 2.D HANDLER READ(P3,缓做)

MySQL 低开销游标接口,PG 等价物 cursor 的快照语义与 HANDLER 的"读当前数据"
不一致,映射不忠实;使用面窄。建议:语法桩返回 1235(ER_NOT_SUPPORTED_YET),
完整映射无限期缓做。

### 2.E ENUM/SET 类型(P2,两期)

- **一期(aux_mysql 域方案)**:按定义自动创建 domain(`varchar(n)+CHECK
  (value IN (...))`),定义文本哈希归一(`mys_enum_<hash>`,同规格全局共用),
  内联 `enum('a','b')`/`set(...)` 在列类型/RETURNS/DECLARE 三处接入点解析到
  canonical domain;随 aux_mysql 版本迁移走。
- **二期(索引语义,深水区)**:按定义序排序、`+0` 取序号、严格模式 1265/
  非严格截断——需要 domain 上加操作符/隐转,单独立项。
- **溢出收益**:普通 DDL 列类型(迁移评估的第一道墙),不止 SP 的 6 条语料。
- 工作量:一期 1–2 周。

### 2.F 对象生命周期/1304(P1,方案已定未实施)

剪依赖方案(2026-09-04 已评审):`mys_ExecDropStmt`(`mys_utility.c:2196+`,
已有 OBJECT_TRIGGER 前置钩子先例)在 drop 前删除**视图指向该函数的 pg_depend
NORMAL 行**(事务内,失败即回滚;`mys_tablecmds.c:3658+/3896+` 有 pg_depend
直改先例),drop 成功后视图留待使用时报 1305(`42883→1305` 映射已存在,
errorConvertor.c:158)。CASCADE 方案(删视图)语义错误,不走。

**推广**:同模式适用于 `DROP TABLE` 带依赖视图(MySQL:成功+视图失效;
PG:RESTRICT 拦/CASCADE 连删)——同一机制一天内一并做。顺带补
`ERRCODE_DEPENDENT_OBJECTS_STILL_EXIST`(2BP000)的错误码映射。

工作量:~1 天含测试;**语料收益最大的单项(+30,编译率直指 ~87%+)**。

### 2.G 权限/账户模型(P3,先调研后立项)

C2 修复后 DEFINER 已是真实执行身份、1227 以 superuser() 代理 SUPER。真正的
MySQL 权限层(GRANT/REVOKE 语法→PG GRANT 映射、SHOW GRANTS、库/表/列级权限
矩阵、mysql.* 授权表从展示对象变权威存储)是独立大项,**不建议为语料而做**;
先调研目标负载(多租户?最小权限部署?审计?)再排期。可选最小切片:MySQL
GRANT 常见形式→PG GRANT 的语法映射(库级→schema ALL、表级→表权限),不动
存储模型。

## 3. 度量与验证基础设施(P0,先于一切)

本轮的教训:回放工具随 /tmp 消失后,文档里的分类已经开始失真(`/*!50003`
版本门控注释标为"待处理",实际 mys_scan.l 已实现且 test_019 覆盖)。因此:

1. **回放工具重建并固化**进 `src/test/mysql`(corpus/ 目录 + CI 可跑的
   看板脚本),分类型统计全量语句 OK/FAIL/OK_NEG/WRONG_ERR/MISSING_ERR,
   不只 CREATE;
2. **语料扩展**:SP 三件套之外补 2–3 份类型/DDL 语料(如 `type_var.test`、
   `enum.test`)作为 beyond-SP 基线——A/C/E 簇的收益在这些语料上才可见;
3. **mysqldump 实样本回归**:test_019 家族增加 `--master-data`/`--flush-logs`
   变体样本(FLUSH 语句的真实入口)。

## 4. 路线图(按投入产出比)

| 序 | 项 | 量级 | 收益 |
|---|---|---|---|
| 1 | 度量基建(回放固化+语料扩展) | 1–2 天 | 后续一切收益可度量;修正文档失真 |
| 2 | 1304 剪依赖 + DROP TABLE 推广 + 2BP000 映射 | ~1 天 | 语料 +30;dump 重建序正确 |
| 3 | FLUSH 一期(全 no-op 档) | 0.5–1 天 | dump 变体可导入;语料 +14 |
| 4 | 维护语句 + leader 三连(ANALYZE/TRUNCATE/RESET) | 1–2 天 | 语料 +8-10;运维工具 |
| 5 | ENUM/SET 一期(域方案) | 1–2 周 | DDL 大盘;迁移评估墙 |
| 6 | LOCK TABLES 真语义(先簿记+gate,后真锁) | 3–5 天+ | 1100 负向 8 条;dump 忠实度 |
| 7 | HANDLER 桩(1235) | 0.5 天 | 错误码正确 |
| 8 | 权限模型调研→(可能)立项 | 调研 2–3 天 | 视需求 |

1–4 完成后编译率预估 **~88–89%**(412→~445/504),全量语句通过率同步改善。

## 5. 待拍板决策点

1. **1304 剪依赖**是否按 §2.F 实施(方案已定,说做即做);
2. **LOCK TABLES** 走 (b) 簿记+gate 还是直上 (a) 真锁(架构取舍,§2.B);
3. **ENUM/SET 一期**是否立项(1–2 周,收益在 DDL 大盘);
4. **权限模型**是否近期做需求调研(§2.G)。

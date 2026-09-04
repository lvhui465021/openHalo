# 触发器功能补完研发方案(2026-09-05)

> 回答的问题:**触发器缺失的功能当前是否可以补完?**
> 结论:**可以。除 1442(需新增一处轻量运行期追踪)外,全部缺口都在当前架构内
> 可修,不需要新的产品决策**;语料口径预估 92% → ~98%。

## 0. 基线

- 编译率 92%(137/149;2026-09-03 差距分析 §2 基线,之后触发器侧无回退)。
- 主体能力已完成并有回归:CREATE/DROP TRIGGER、单语句与 BEGIN...END 体、
  OLD./NEW.、definer 真实执行身份(2026-09-05 C2,proconfig 路径)、
  mysqldump 直通(版本门控注释)、1359 同 schema 唯一、1361 视图/临时表、
  1465 系统 schema、1424 间接递归、1415/1336(结果集/动态 SQL 拒绝)、
  SHOW TRIGGERS(mys_gram.y:3843)、SHOW CREATE TRIGGER(:3901 +
  mysql.show_create_trigger,aux_mysql--1.8--1.9.sql:61)、
  information_schema 触发器视图(aux_mysql 1.9)。

## 1. 缺口清单(全部经代码/语料核实)

### 正向缺口(功能不存在)

| # | 缺口 | 证据 | 语料驱动 |
|---|---|---|---|
| T1 | **长 DEFINER 主机名** | 词法标识符路径 63 字节静默截断(mys_scan.l:833/1000/1289 → scansup.c:96-108,仅 NOTICE);trigger.test 最长 DEFINER 串 97 字符 | **+4**(触发器与 SP 共享同一失败桶) |
| T2 | **FOLLOWS/PRECEDES 触发器排序子句**(MySQL 5.7.2+) | mys_gram.y 零出现;trigger.test 亦零条(不在 12 条失败内,但同事件多触发器的**确定性顺序**是迁移评估检查项) | 0 |
| T3 | **DEFINER=CURRENT_USER 书写** | `user:` 产生式只收 RoleId(mys_gram.y:11394-11397),CURRENT_USER 走不进去;语料与 mysqldump 均 0 条 | 0 |
| T4 | **限定名触发器/跨 schema** | 语法不支持给触发器名单独 schema(backlog 记录;语料 0 条) | 0 |

### 负向缺口(该报错未按 MySQL 报)

| # | 缺口 | 证据 | 语料驱动 |
|---|---|---|---|
| T5 | **1313 RETURN 出现在触发器体** | 一次实测失败记录:plmysql 语法层直接拦会误伤包装层自动注入的 `RETURN NEW`(mys_mysql_trigger_function_body,mys_utility.c:457-484——PG 触发器函数协议要求) | +1-2 |
| T6 | **1422 隐式提交 DDL 在函数/触发器内** | 现只拦字面 COMMIT/ROLLBACK(pl_gram.y:2016-2037 → mysql_check_transaction_context :2876-2888);DDL 作 T_WORD 直通 | +4(与函数共享) |
| T7 | **1442 修改正被触发语句使用的表** | 无任何"当前语句正在用哪些表"的追踪(backlog 归档:调用链级新基础设施) | +3 |

另:12 条失败中约 3 条疑似 `/*!50003` 版本门控注释桶——mys_scan.l:525-558
**已实现**(test_019 覆盖),差距分析文档归类过时,重测即回收,无需开发。

## 2. 逐项方案

### T1 长 DEFINER 主机名(P1,0.5-1 天)

根因是**类别错误**:definer 的 host 走了标识词法路径被 NAMEDATALEN 截断,
而它的实际去处(security label / proconfig,均为 text)**根本没有长度限制**。
方案:为 definer host 加专用词法规则,像 `MysqlUserVariable` 那样
`pstrdup(yytext)` 原样捕获——不截断、不小写(definer 是元数据不是标识符);
文法 `user:` 产生式接新 token。触发器与 SP 一次修复共享收益。
风险:低(纯增量路径,不动既有 RoleId 语义)。

### T2 FOLLOWS/PRECEDES(P2,2-3 天,方案要点)

三层:①文法接受 `[FOLLOWS|PRECEDES] other_trigger`;②声明的顺序记入
plmysql meta(展示/SHOW 用);③**真实 firing 顺序**——PG 对同事件多触发器
按名字字母序触发,不可配;方案:把声明顺序编码进底层 PG 触发器名
(`__mysql_trigger_<序号>_<名>`,字母序即声明序)。
**连动风险**:私有触发器名约定被 DROP TRIGGER 解析(:558+
mys_preprocess_mysql_drop_trigger)与 `mys_trigger_has_mysql_name`(:541)
依赖,命名变更须同步这两处并全量回归(含 1359 唯一性)。

### T3 DEFINER=CURRENT_USER(P3,0.5 天)

`user:` 产生式加 `CURRENT_USER`(带/不带括号)备选,解析为当前用户
`GetUserNameFromId(GetUserId()) + "@%"` 即可,后续路径不变。

### T4 限定名触发器 + 1435(P3,1 天)

文法扩限定名(schema.trig);随后加一致性检查:触发器名 schema ≠ 表
schema 时报 MySQL 1435(ER_TRG_IN_WRONG_SCHEMA)。注意 mysqldump 触发器
段总是 `USE db` + 限定的 `CREATE TRIGGER db.t`,**限定名形式本身是 dump
路径的真实需求**,1435 检查是顺带的对齐完备性。

### T5 1313 RETURN 扫描(P1,0.5-1 天)

避开包装层注入的 `RETURN NEW` 的关键:**扫描原始 MySQL 触发器体**,不动
plmysql 语法层。实现:在 mys_make_mysql_trigger_function() 拿到原始 body
文本后,做一遍词法扫描(复用 mys 词法对字符串字面量/注释/反引号 ident 的
处理规则),发现顶层语句起始处的 `RETURN` token 即
mysSetPendingMySQLErrno(1313) 报
"RETURN is only allowed in a FUNCTION"。同样的扫描可顺带覆盖
过程体的 1313(MySQL 里 RETURN 在 PROCEDURE 同样非法)——同一份代码
两个消费方。

### T6 1422 隐式提交(P1,1-2 天,与函数共享)

双层:①编译期首 token 嗅探——仿已有先例
mysql_check_dynamic_sql_context(pl_gram.y:2846-2867,对 1336 就是这么做的),
把 MySQL 隐式提交语句首词清单(CREATE/ALTER/DROP/RENAME/TRUNCATE/
GRANT/REVOKE/FLUSH/LOCK TABLES/SET AUTOCOMMIT 等,按 MySQL 5.7
"导致隐式提交的语句"官方清单整理)在 FUNCTION/触发器上下文里拦 1422;
②执行期兜底——SPI 执行后看 commandTag(pl_exec.c:4169 有先例),
防止动态 SQL/拼串绕过编译期检查。
风险:清单要精确——过宽会误拦(MySQL 里部分 CREATE 不隐式提交,如
CREATE TEMPORARY TABLE... 其实在 5.7 也隐式提交?需按官方表逐条核对),
建议照抄官方清单并留 TODO 注释标来源。

### T7 1442 修改正被使用的表(P3 单列,2-4 天,唯一需要新设施的项)

需要"外层触发语句正在读/写哪些表"对触发器内写语句可见:
①插点:openHalo fork 了执行器(mys_execMain.c),在 MySQL 协议 DML 执行
入口把 PlannedStmt 的 range table Oid 集合快照进 backend-local 变量
(只记 Oid 集合,每语句开销可忽略);②触发器内写语句 plan 时(或 SPI
prepare 后)比对 target relid ∈ 集合,命中即 1442(MySQL 文案
"Can't update table 'x' in stored function/trigger because it is already
used by statement which invoked it")。
风险:MySQL"正在使用"的精确定义(outer 语句 READ 或 WRITE 的表都算)
要对齐,过宽会误伤级联触发器的合法场景(表 A 触发器写表 B、B 又触发)
——级联场景 outer 集合应随触发深度重算。建议先只覆盖单层(outer 最外层
DML),嵌套行为实测 MySQL 后再定。

### 前置:T0 回放工具重建(P0,1-2 天,与 beyond-SP 方案共用)

12 条失败的确切构成目前是推断(长 definer ~4 + 版本注释 ~3(疑已修)+ 其余
未证);不重建回放工具,收尾阶段无法验收"补完"。

## 3. 排序与总量

| 序 | 项 | 量级 | 语料 |
|---|---|---|---|
| 0 | T0 回放工具重建 | 1-2 天 | 度量前提 |
| 1 | T1 长 DEFINER(词法) | 0.5-1 天 | +4 |
| 2 | T5 1313(原始体扫描) | 0.5-1 天 | +1-2 |
| 3 | T6 1422(编译期+执行期) | 1-2 天 | +4 |
| 4 | T2 FOLLOWS/PRECEDES | 2-3 天 | 0(真实功能) |
| 5 | T4 限定名+1435 | 1 天 | 0(dump 路径) |
| 6 | T3 DEFINER=CURRENT_USER | 0.5 天 | 0 |
| 7 | T7 1442(新设施,单列评审) | 2-4 天 | +3 |

- **不含 T7:约 6-10 天**,语料口径预估 137/149 → ~146-147/149(**~98%**,
  剩余为语料里的 SP 共享失败如括号 SELECT 等,不在触发器侧);
- **含 T7:约 9-14 天**;T7 是唯一超出"当前架构局部修改"的项,建议实施前
  单独评审(性能与误报边界),不与 1-6 捆绑。

## 4. 风险与边界

- T2 命名方案变更牵动 DROP TRIGGER/1359/回放与 mysqldump 往返,需全量
  回归 + dump 导入用例;
- T6 清单精确性(照抄 MySQL 官方隐式提交表,标注来源);
- T7 误报边界(级联触发器),首版只做单层;
- 已知非目标:触发器 SQL SECURITY 子句(MySQL 触发器没有这个子句,只有
  DEFINER——已随 C2 落地);HANDLER 与 FLUSH 触发器无关,见 beyond-SP 设计。

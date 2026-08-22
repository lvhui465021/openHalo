# M1: plmysql 引擎骨架与过程体捕获 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 MySQL 客户端能执行 `CREATE PROCEDURE p() BEGIN DECLARE v INT DEFAULT 1; SET v = v + 1; END;` 并成功 `CALL p()`。

**Architecture:** 在 `mys_gram.y` 增加"过程体原文整体截取"产生式（Babelfish `tokens_remaining` 技巧），把 MySQL 裸 `BEGIN...END` 体当作字符串存入 `pg_proc.prosrc`，`language` 固定为 `plmysql`，复用 PostgreSQL 原生 `CreateFunction()` DDL 路径。新增 `src/pl/plmysql/` 过程语言（克隆自 `src/pl/plpgsql/`，符号前缀改名后替换语法层为 MySQL SQL/PSM）。

**Tech Stack:** C (PostgreSQL 14.23 backend)、bison/flex、Python 3.6+ with pymysql（测试）、GNU make

## Global Constraints

- 基线 PostgreSQL 版本：14.23（`configure.ac:20` `AC_INIT([Halo], [14.23], ...)`）
- 对标标准：MySQL 5.7 Reference Manual §13.1.16 / §13.6.x
- 设计文档：`docs/superpowers/specs/2026-08-22-openhalo-mysql-stored-procedure-design.md`
- 新增 C 源文件必须带 openHalo 版权头（复制自 `src/backend/commands/mysql/mys_uservar.c` 的头部注释块，改 `IDENTIFICATION` 路径）
- 过程语言名固定为 `plmysql`（小写），符号前缀 `plmysql_` / `PLMySQL_` / `PLMYSQL_`
- **不修改 `src/pl/plpgsql/` 下任何文件**——该目录被 `AUTO_INCREMENT` 触发器链路（`src/backend/parser/mysql/mys_parse_utilcmd.c:849-938`）在役依赖，污染风险不可接受
- 所有测试必须走 MySQL 协议（3306），不能用 `pg_regress`——原因见 Task 1 背景说明
- 提交信息格式：`feat(plmysql): <描述>` / `test(plmysql): <描述>` / `build: <描述>`

---

## 背景：为什么不能用 pg_regress

`contrib/aux_mysql/Makefile` 有 `REGRESS_OPTS = --temp-config .../mysql.conf`，且 `mysql.conf` 内容是 `database_compat_mode = 'mysql'`，看起来像是现成的测试通道。**但它不能用于本计划**：

`src/backend/parser/parsereng.c:44-56` 的引擎选择逻辑：

```c
case MYSQL_COMPAT_MODE:
    if ((MyProcPort != NULL) &&
        (nodeTag(MyProcPort->protocol_handler) == T_MySQLProtocol))
    {
        parserengine = GetMysParserEngine();
    }
    else
    {
        parserengine = GetStandardParserEngine();
    }
    break;
```

`pg_regress` 通过 psql（PostgreSQL 协议）连接，`protocol_handler` 不是 `T_MySQLProtocol`，因此即使 `database_compat_mode = 'mysql'`，拿到的仍是**标准 PostgreSQL 解析器**，`mys_gram.y` 的任何改动都不会被触发。`src/backend/executor/executor_engine.c:44-58` 的 `InitExecutorEngine()` 有完全相同的判断。

因此 Task 1 必须先建立 MySQL 协议测试通道。

---

## File Structure

**新建目录 `src/test/mysql/`** — MySQL 协议集成测试（Python + pymysql）

| 文件 | 职责 |
|---|---|
| `src/test/mysql/halo_cluster.py` | 集群生命周期管理：initdb、配置写入、启停、连接工厂。只做进程和连接管理，不含断言逻辑 |
| `src/test/mysql/run_tests.py` | 测试发现与执行入口，返回非零退出码表示失败 |
| `src/test/mysql/t/test_001_plmysql_skeleton.py` | Task 2 的测试 |
| `src/test/mysql/t/test_002_routine_body_capture.py` | Task 3 的测试 |
| `src/test/mysql/t/test_003_declare_set.py` | Task 4/5 的测试 |
| `src/test/mysql/t/test_004_protocol_scope.py` | Task 6 的测试 |
| `src/test/mysql/Makefile` | `make check` 入口 |

**新建目录 `src/pl/plmysql/`** — MySQL 过程语言（克隆自 `src/pl/plpgsql/`）

| 文件 | 职责 |
|---|---|
| `src/pl/plmysql/Makefile` | 递归到 `src/` |
| `src/pl/plmysql/src/Makefile` | 共享库构建、bison/flex 规则、关键字表生成 |
| `src/pl/plmysql/src/plmysql.control` | 扩展元数据 |
| `src/pl/plmysql/src/plmysql--1.0.sql` | 语言注册（handler/validator/inline） |
| `src/pl/plmysql/src/plmysql.h` | 数据结构定义（自 `plpgsql.h`，1325 行） |
| `src/pl/plmysql/src/pl_handler.c` | 语言入口、GUC、协议作用域检查（自 551 行） |
| `src/pl/plmysql/src/pl_comp.c` | 编译器（自 2682 行） |
| `src/pl/plmysql/src/pl_exec.c` | 执行器（自 8793 行，本计划内**不做语义改动**） |
| `src/pl/plmysql/src/pl_funcs.c` | 语句节点辅助函数（自 1692 行） |
| `src/pl/plmysql/src/pl_gram.y` | 语法（自 4162 行，Task 5 替换块结构） |
| `src/pl/plmysql/src/pl_scanner.c` | 词法（自 637 行） |
| `src/pl/plmysql/src/pl_reserved_kwlist.h` | 保留关键字表 |
| `src/pl/plmysql/src/pl_unreserved_kwlist.h` | 非保留关键字表 |
| `src/pl/plmysql/src/generate-plerrcodes.pl` | 错误码头文件生成脚本 |

**修改**

| 文件 | 改动 |
|---|---|
| `src/pl/Makefile:15` | `SUBDIRS = plpgsql` → `SUBDIRS = plpgsql plmysql` |
| `contrib/aux_mysql/aux_mysql.control` | 增加 `requires = 'plmysql'` |
| `src/backend/parser/mysql/mys_gram.y` | 新增过程体捕获产生式与 `CreateFunctionStmt` MySQL 分支 |
| `src/include/parser/mysql/mys_gramparse.h` | 声明捕获辅助函数 |

---

### Task 1: MySQL 协议测试脚手架

**Files:**
- Create: `src/test/mysql/halo_cluster.py`
- Create: `src/test/mysql/run_tests.py`
- Create: `src/test/mysql/Makefile`
- Create: `src/test/mysql/t/__init__.py`（空文件）
- Create: `src/test/mysql/t/test_000_smoke.py`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces:
  - `halo_cluster.HaloCluster(bindir: str, basedir: str, pg_port: int = 55432, mysql_port: int = 53306)`
  - `HaloCluster.setup() -> None`（initdb + 写配置 + 启动 + `CREATE EXTENSION aux_mysql CASCADE`）
  - `HaloCluster.teardown() -> None`
  - `HaloCluster.mysql() -> pymysql.Connection`（MySQL 协议连接，`autocommit=True`）
  - `HaloCluster.psql(sql: str) -> str`（PostgreSQL 协议执行，返回 stdout）
  - 测试模块约定：每个 `t/test_*.py` 暴露 `run(cluster: HaloCluster) -> None`，断言失败抛异常

- [ ] **Step 1: 写集群管理模块**

创建 `src/test/mysql/halo_cluster.py`：

```python
"""openHalo 测试集群生命周期管理（MySQL 协议集成测试用）。

用法:
    c = HaloCluster(bindir="/path/to/install/bin", basedir="/tmp/halotest")
    c.setup()
    try:
        with c.mysql() as conn: ...
    finally:
        c.teardown()
"""
import os
import shutil
import socket
import subprocess
import time

import pymysql


class HaloCluster:
    def __init__(self, bindir, basedir, pg_port=55432, mysql_port=53306):
        self.bindir = bindir
        self.basedir = basedir
        self.datadir = os.path.join(basedir, "data")
        self.sockdir = os.path.join(basedir, "sock")
        self.logfile = os.path.join(basedir, "server.log")
        self.pg_port = pg_port
        self.mysql_port = mysql_port

    def _bin(self, name):
        return os.path.join(self.bindir, name)

    def _run(self, argv, **kw):
        env = dict(os.environ)
        env["PGHOST"] = self.sockdir
        env["PGPORT"] = str(self.pg_port)
        return subprocess.run(argv, check=True, capture_output=True,
                              text=True, env=env, **kw)

    def setup(self):
        if os.path.exists(self.basedir):
            shutil.rmtree(self.basedir)
        os.makedirs(self.sockdir)
        self._run([self._bin("initdb"), "-D", self.datadir, "--no-sync",
                   "-U", "halo", "-E", "UTF8"])
        with open(os.path.join(self.datadir, "postgresql.conf"), "a") as f:
            f.write("\n# --- openHalo MySQL integration test ---\n")
            f.write("database_compat_mode = 'mysql'\n")
            f.write("mysql.listener_on = true\n")
            f.write("mysql.port = %d\n" % self.mysql_port)
            f.write("port = %d\n" % self.pg_port)
            f.write("listen_addresses = '127.0.0.1'\n")
            f.write("unix_socket_directories = '%s'\n" % self.sockdir)
            f.write("search_path = '\"$user\", public, mysql, pg_catalog'\n")
        self._run([self._bin("pg_ctl"), "-D", self.datadir, "-l", self.logfile,
                   "-w", "start"])
        self._wait_for_port(self.mysql_port)
        self.psql("CREATE EXTENSION aux_mysql CASCADE;")

    def _wait_for_port(self, port, timeout=30.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", port), 1.0):
                    return
            except OSError:
                time.sleep(0.2)
        raise RuntimeError("port %d not listening within %.0fs; see %s"
                           % (port, timeout, self.logfile))

    def teardown(self):
        try:
            self._run([self._bin("pg_ctl"), "-D", self.datadir, "-m",
                       "immediate", "-w", "stop"])
        except Exception:
            pass

    def psql(self, sql, dbname="postgres"):
        r = self._run([self._bin("psql"), "-X", "-q", "-A", "-t",
                       "-v", "ON_ERROR_STOP=1", "-d", dbname, "-c", sql])
        return r.stdout

    def mysql(self, dbname="postgres"):
        return pymysql.connect(host="127.0.0.1", port=self.mysql_port,
                               user="halo", database=dbname,
                               autocommit=True, charset="utf8mb4")
```

- [ ] **Step 2: 写测试运行器**

创建 `src/test/mysql/run_tests.py`：

```python
#!/usr/bin/env python3
"""发现并运行 t/test_*.py 中的 run(cluster) 函数。

用法: python3 run_tests.py <bindir> [basedir]
退出码 0 表示全部通过。
"""
import importlib.util
import glob
import os
import sys
import traceback

from halo_cluster import HaloCluster


def load(path):
    name = os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return name, mod


def main():
    if len(sys.argv) < 2:
        print("usage: run_tests.py <bindir> [basedir]", file=sys.stderr)
        return 2
    bindir = sys.argv[1]
    basedir = sys.argv[2] if len(sys.argv) > 2 else "/tmp/halo_mysql_test"
    here = os.path.dirname(os.path.abspath(__file__))
    tests = sorted(glob.glob(os.path.join(here, "t", "test_*.py")))

    cluster = HaloCluster(bindir=bindir, basedir=basedir)
    cluster.setup()
    failed = []
    try:
        for path in tests:
            name, mod = load(path)
            if not hasattr(mod, "run"):
                continue
            try:
                mod.run(cluster)
                print("ok - %s" % name)
            except Exception:
                failed.append(name)
                print("not ok - %s" % name)
                traceback.print_exc()
    finally:
        cluster.teardown()

    print("\n%d/%d passed" % (len(tests) - len(failed), len(tests)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: 写 Makefile 与冒烟测试**

创建 `src/test/mysql/Makefile`：

```makefile
# src/test/mysql/Makefile

subdir = src/test/mysql
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

PYTHON ?= python3
TESTBASEDIR ?= $(CURDIR)/tmp_check

check:
	$(PYTHON) $(srcdir)/run_tests.py '$(bindir)' '$(TESTBASEDIR)'

clean distclean maintainer-clean:
	rm -rf $(TESTBASEDIR)

.PHONY: check
```

创建 `src/test/mysql/t/__init__.py`（内容为空）。

创建 `src/test/mysql/t/test_000_smoke.py`：

```python
"""验证测试脚手架本身可用：MySQL 协议可连、可执行查询。"""


def run(cluster):
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            row = cur.fetchone()
            assert row == (1,), "expected (1,), got %r" % (row,)
```

- [ ] **Step 4: 运行冒烟测试确认脚手架可用**

先确保 openHalo 已构建安装（若尚未安装）：

```bash
cd /home/unvdb/pg_github/openHalo && ./configure --prefix=$PWD/tmp_install --enable-debug --with-uuid=ossp --with-icu CFLAGS=-O0 && make -j$(nproc) && make install && cd contrib && make && make install
```

运行：

```bash
cd /home/unvdb/pg_github/openHalo/src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `ok - test_000_smoke` 与 `1/1 passed`，退出码 0。

若 `pymysql` 缺失，先 `pip3 install pymysql`。

- [ ] **Step 5: Commit**

```bash
git add src/test/mysql
git commit -m "test(plmysql): add MySQL protocol integration test harness"
```

---

### Task 2: plmysql 扩展骨架（克隆 plpgsql）

本任务只做**克隆与改名**，不改任何语法/语义。产出物是一个功能上等价于 plpgsql、但以 `plmysql` 名字注册的独立过程语言。这样后续任务可以在一个已知可工作的基础上逐步替换语法层。

**Files:**
- Create: `src/pl/plmysql/Makefile`
- Create: `src/pl/plmysql/src/Makefile`
- Create: `src/pl/plmysql/src/plmysql.control`
- Create: `src/pl/plmysql/src/plmysql--1.0.sql`
- Create: `src/pl/plmysql/src/{plmysql.h,pl_comp.c,pl_exec.c,pl_funcs.c,pl_gram.y,pl_handler.c,pl_scanner.c,pl_reserved_kwlist.h,pl_unreserved_kwlist.h,generate-plerrcodes.pl}`
- Modify: `src/pl/Makefile:15`
- Modify: `contrib/aux_mysql/aux_mysql.control`
- Test: `src/test/mysql/t/test_001_plmysql_skeleton.py`

**Interfaces:**
- Consumes: `halo_cluster.HaloCluster`（Task 1）
- Produces:
  - SQL 层：语言 `plmysql`，函数 `plmysql_call_handler()`、`plmysql_inline_handler(internal)`、`plmysql_validator(oid)`
  - C 层符号前缀：`plmysql_*`（110 个标识符）、`PLMySQL_*`（60 个）、`PLMYSQL_*`（91 个）
  - bison 前缀：`plmysql_yy`
  - 共享库：`$libdir/plmysql`

- [ ] **Step 1: 写失败测试**

创建 `src/test/mysql/t/test_001_plmysql_skeleton.py`：

```python
"""plmysql 语言已注册且可用（此阶段语法仍等价于 plpgsql）。"""


def run(cluster):
    # 语言存在
    out = cluster.psql("SELECT lanname FROM pg_language WHERE lanname='plmysql';")
    assert out.strip() == "plmysql", "plmysql language not registered: %r" % out

    # 三个 handler 函数存在
    out = cluster.psql(
        "SELECT count(*) FROM pg_proc WHERE proname IN "
        "('plmysql_call_handler','plmysql_inline_handler','plmysql_validator');")
    assert out.strip() == "3", "expected 3 handler functions, got %r" % out

    # 能以 plmysql 创建并执行函数（走 PG 协议，此时用 plpgsql 语法）
    cluster.psql("""
        CREATE FUNCTION t001_add(a int, b int) RETURNS int
        LANGUAGE plmysql AS $$ BEGIN RETURN a + b; END $$;
    """)
    out = cluster.psql("SELECT t001_add(2, 3);")
    assert out.strip() == "5", "expected 5, got %r" % out

    # 与 plpgsql 是相互独立的两个语言，plpgsql 未被破坏
    cluster.psql("""
        CREATE FUNCTION t001_mul(a int, b int) RETURNS int
        LANGUAGE plpgsql AS $$ BEGIN RETURN a * b; END $$;
    """)
    out = cluster.psql("SELECT t001_mul(2, 3);")
    assert out.strip() == "6", "plpgsql regression: expected 6, got %r" % out
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /home/unvdb/pg_github/openHalo/src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `not ok - test_001_plmysql_skeleton`，异常信息为 `plmysql language not registered: ''`。

- [ ] **Step 3: 克隆源码树并批量改名**

```bash
cd /home/unvdb/pg_github/openHalo
cp -r src/pl/plpgsql src/pl/plmysql
rm -rf src/pl/plmysql/src/expected src/pl/plmysql/src/sql \
       src/pl/plmysql/src/input src/pl/plmysql/src/output
rm -f src/pl/plmysql/src/plpgsql.control src/pl/plmysql/src/plpgsql--1.0.sql
rm -f src/pl/plmysql/src/pl_gram.c src/pl/plmysql/src/pl_gram.h \
      src/pl/plmysql/src/plerrcodes.h \
      src/pl/plmysql/src/pl_reserved_kwlist_d.h \
      src/pl/plmysql/src/pl_unreserved_kwlist_d.h \
      src/pl/plmysql/src/*.o src/pl/plmysql/src/*.so
mv src/pl/plmysql/src/plpgsql.h src/pl/plmysql/src/plmysql.h

# 符号前缀改名（顺序重要：先长后短，避免 PLpgSQL_ 被 plpgsql_ 规则误伤）
cd src/pl/plmysql/src
sed -i \
  -e 's/\bPLPGSQL_/PLMYSQL_/g' \
  -e 's/\bPLpgSQL_/PLMySQL_/g' \
  -e 's/\bplpgsql_/plmysql_/g' \
  -e 's/PLPGSQL_H/PLMYSQL_H/g' \
  -e 's/"plpgsql\.h"/"plmysql.h"/g' \
  -e 's/\bplpgsql\b/plmysql/g' \
  -e 's/PL\/pgSQL/PL\/MySQL/g' \
  *.c *.h *.y generate-plerrcodes.pl
```

改名后核对无遗留（应输出 0）：

```bash
cd /home/unvdb/pg_github/openHalo/src/pl/plmysql/src && grep -c "plpgsql\|PLpgSQL\|PLPGSQL" *.c *.h *.y | grep -v ":0" | wc -l
```

- [ ] **Step 4: 写扩展控制文件与注册 SQL**

创建 `src/pl/plmysql/src/plmysql.control`：

```
# plmysql extension
comment = 'PL/MySQL procedural language for MySQL compatibility mode'
default_version = '1.0'
module_pathname = '$libdir/plmysql'
relocatable = false
schema = pg_catalog
superuser = true
trusted = true
```

创建 `src/pl/plmysql/src/plmysql--1.0.sql`：

```sql
/* src/pl/plmysql/src/plmysql--1.0.sql */

CREATE FUNCTION plmysql_call_handler() RETURNS language_handler
  LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION plmysql_inline_handler(internal) RETURNS void
  STRICT LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION plmysql_validator(oid) RETURNS void
  STRICT LANGUAGE c AS 'MODULE_PATHNAME';

CREATE TRUSTED LANGUAGE plmysql
  HANDLER plmysql_call_handler
  INLINE plmysql_inline_handler
  VALIDATOR plmysql_validator;

ALTER LANGUAGE plmysql OWNER TO @extowner@;

COMMENT ON LANGUAGE plmysql IS 'PL/MySQL procedural language';
```

- [ ] **Step 5: 改构建文件**

替换 `src/pl/plmysql/Makefile` 全文：

```makefile
#-------------------------------------------------------------------------
#
# Makefile for src/pl/plmysql (openHalo MySQL procedural language)
#
# src/pl/plmysql/Makefile
#
#-------------------------------------------------------------------------

subdir = src/pl/plmysql
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

SUBDIRS = src

$(recurse)
```

在 `src/pl/plmysql/src/Makefile` 中做如下替换（该文件是从 plpgsql 复制来的，改这些点）：

```
subdir = src/pl/plpgsql/src        →  subdir = src/pl/plmysql/src
PGFILEDESC = "PL/pgSQL - ..."      →  PGFILEDESC = "PL/MySQL - procedural language"
NAME= plpgsql                      →  NAME= plmysql
DATA = plpgsql.control plpgsql--1.0.sql  →  DATA = plmysql.control plmysql--1.0.sql
```

同时把该 Makefile 中所有 `plpgsql.h` 改为 `plmysql.h`，`--varname ReservedPLKeywords` 改为 `--varname ReservedPLMySQLKeywords`，`--varname UnreservedPLKeywords` 改为 `--varname UnreservedPLMySQLKeywords`，并删除整个 `REGRESS = ...` 赋值以及 `check:`/`installcheck:`/`submake` 三个目标及其 `.PHONY: submake`（plmysql 不用 pg_regress，见本计划背景说明）。相应地也要把 `pl_scanner.c` 中引用的 `ReservedPLKeywords`/`UnreservedPLKeywords` 同步改名。

修改 `src/pl/Makefile:15`：

```makefile
SUBDIRS = plpgsql plmysql
```

修改 `contrib/aux_mysql/aux_mysql.control`，追加一行：

```
requires = 'plmysql'
```

- [ ] **Step 6: 构建并运行测试确认通过**

```bash
cd /home/unvdb/pg_github/openHalo && make -j$(nproc) && make install && cd src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `ok - test_000_smoke`、`ok - test_001_plmysql_skeleton`，`2/2 passed`。

- [ ] **Step 7: Commit**

```bash
git add src/pl/plmysql src/pl/Makefile contrib/aux_mysql/aux_mysql.control src/test/mysql/t/test_001_plmysql_skeleton.py
git commit -m "feat(plmysql): clone plpgsql into plmysql procedural language skeleton"
```

---

### Task 3: mys_gram.y 过程体原文捕获

**Files:**
- Modify: `src/backend/parser/mysql/mys_gram.y`（`CreateFunctionStmt` 产生式区，约 11069-11123 行；`opt_routine_body` 区，约 11582-11601 行）
- Modify: `src/include/parser/mysql/mys_gramparse.h`
- Test: `src/test/mysql/t/test_002_routine_body_capture.py`

**Interfaces:**
- Consumes: Task 2 的 `plmysql` 语言注册
- Produces:
  - bison 产生式 `mysql_routine_body`，归约结果为 `char *`（过程体原文，含外层 `BEGIN`/`END`）
  - C 辅助函数 `char *mys_capture_routine_body(core_yyscan_t yyscanner, int body_start_loc)`，声明于 `mys_gramparse.h`
  - `CreateFunctionStmt.options` 中固定包含 `makeDefElem("language", (Node *)makeString("plmysql"), -1)` 与 `makeDefElem("as", (Node *)list_make1(makeString(body)), -1)`

- [ ] **Step 1: 写失败测试**

创建 `src/test/mysql/t/test_002_routine_body_capture.py`：

```python
"""MySQL 协议下裸 BEGIN...END 过程体可被捕获并存入 pg_proc.prosrc。

此阶段 plmysql 语法仍等价于 plpgsql，因此过程体用两种语法都能解析的写法。
"""


def run(cluster):
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t002_p")
            cur.execute("CREATE PROCEDURE t002_p() BEGIN NULL; END")

    # 语言必须是 plmysql，不是 sql
    out = cluster.psql(
        "SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang "
        "WHERE p.proname='t002_p';")
    assert out.strip() == "plmysql", "expected plmysql, got %r" % out

    # prosrc 必须是原文（含 BEGIN/END），不是被解析后重构的
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_p';")
    src = out.strip()
    assert src.upper().startswith("BEGIN"), "prosrc should start with BEGIN: %r" % src
    assert src.upper().rstrip(";").endswith("END"), "prosrc should end with END: %r" % src

    # prokind 是 procedure
    out = cluster.psql("SELECT prokind FROM pg_proc WHERE proname='t002_p';")
    assert out.strip() == "p", "expected prokind=p, got %r" % out

    # 嵌套 BEGIN...END 不能提前截断
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t002_nested")
            cur.execute("CREATE PROCEDURE t002_nested() "
                        "BEGIN BEGIN NULL; END; NULL; END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_nested';")
    src = out.strip()
    assert src.count("BEGIN") == 2, "nested BEGIN lost: %r" % src
    assert src.upper().rstrip(";").endswith("END"), "truncated at inner END: %r" % src
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /home/unvdb/pg_github/openHalo/src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `not ok - test_002_routine_body_capture`，pymysql 抛语法错误（当前 `opt_routine_body` 只接受 `BEGIN ATOMIC`）。

- [ ] **Step 3: 在 mys_gramparse.h 声明捕获函数**

修改 `src/include/parser/mysql/mys_gramparse.h`，在 `extern int mys_yyparse(core_yyscan_t yyscanner);` 之前插入：

```c
/*
 * Capture the raw text of a MySQL routine body (a bare BEGIN ... END block,
 * which unlike PostgreSQL's dollar-quoted bodies has no delimiters).  Consumes
 * tokens from the scanner without interpreting them, tracking nesting of
 * BEGIN/END, IF/END IF, LOOP/END LOOP, CASE/END CASE, WHILE/END WHILE and
 * REPEAT/END REPEAT, then returns a palloc'd substring of the original input.
 *
 * body_start_loc is the scanner offset of the opening BEGIN token.
 */
extern char *mys_capture_routine_body(core_yyscan_t yyscanner,
									  int body_start_loc);
```

- [ ] **Step 4: 实现捕获函数**

在 `src/backend/parser/mysql/mys_gram.y` 文件末尾的 C 代码区（`%%` 之后的辅助函数区，与 `base_yylex`/其他 `mys_*` 辅助函数同一区域）追加：

```c
/*
 * mys_capture_routine_body
 *
 * See the header comment in mys_gramparse.h.  This is the openHalo analogue of
 * the technique Babelfish uses for T-SQL routine bodies: rather than teaching
 * the top-level SQL grammar the whole procedural language, swallow the body as
 * uninterpreted text and let the plmysql compiler parse it later.
 */
char *
mys_capture_routine_body(core_yyscan_t yyscanner, int body_start_loc)
{
	mys_yy_extra_type *yyextra = mys_yyget_extra(yyscanner);
	YYSTYPE		lval;
	YYLTYPE		lloc;
	int			tok;
	int			pending = -1;   /* token already lexed but not yet classified */
	YYLTYPE		pending_loc = 0;
	int			depth = 1;      /* the opening BEGIN */
	int			end_loc = -1;
	char	   *buf = yyextra->core_yy_extra.scanbuf;
	char	   *body;

	/*
	 * This loop owns the token stream until the matching END, so it can look
	 * ahead freely: a token that turns out to belong to the next construct is
	 * simply carried over in `pending` and classified on the next iteration.
	 * No pushback into the scanner is needed.
	 */
	for (;;)
	{
		if (pending >= 0)
		{
			tok = pending;
			lloc = pending_loc;
			pending = -1;
		}
		else
		{
			tok = mys_yylex(&lval, &lloc, yyscanner);
		}

		if (tok == 0)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("unterminated routine body: missing END")));

		switch (tok)
		{
			case BEGIN_P:
			case CASE:
			case LOOP:
			case WHILE:
			case REPEAT:
				depth++;
				break;

			case IF_P:
				{
					/*
					 * Statement-position IF opens a block; the IF(a,b,c)
					 * function-call form does not.  Distinguish by the next
					 * token: '(' means the function form.
					 */
					int		next = mys_yylex(&lval, &lloc, yyscanner);

					if (next != '(')
						depth++;
					pending = next;
					pending_loc = lloc;
					continue;
				}

			case END_P:
				{
					/*
					 * "END IF" / "END LOOP" / "END CASE" / "END WHILE" /
					 * "END REPEAT" close one nesting level, and so does a bare
					 * "END".  Consume the optional trailing keyword here so the
					 * main switch never sees it as an opener.
					 */
					int		close_loc = lloc;
					int		next = mys_yylex(&lval, &lloc, yyscanner);

					if (next != IF_P && next != LOOP && next != CASE &&
						next != WHILE && next != REPEAT)
					{
						pending = next;
						pending_loc = lloc;
					}

					depth--;
					if (depth == 0)
					{
						end_loc = close_loc;
						goto done;
					}
					continue;
				}

			default:
				break;
		}
	}

done:
	/* end_loc is the offset of the final END; include the keyword itself. */
	body = palloc(end_loc - body_start_loc + 4);
	memcpy(body, buf + body_start_loc, end_loc - body_start_loc + 3);
	body[end_loc - body_start_loc + 3] = '\0';

	return body;
}
```

> **实现者注意**：`END_P` 分支在 `depth` 归零时通过 `goto done` 跳出，此时可能已经多读了一个 token（`pending`）——这没有问题，因为该 token 属于 `CREATE PROCEDURE` 语句之后的内容（通常是 `;` 或 EOF），主语法不再需要它。若实测发现主语法在 `mysql_routine_body` 归约后仍需要该 token，改为在 `depth == 0` 时不做前瞻。

- [ ] **Step 5: 增加语法产生式**

在 `src/backend/parser/mysql/mys_gram.y` 的 `opt_routine_body` 产生式（约 11582 行）**之前**插入新产生式：

```
mysql_routine_body:
			BEGIN_P
				{
					$$ = mys_capture_routine_body(yyscanner, @1);
				}
		;
```

在 `%type <str>` 声明区（与其他 `<str>` 类型的非终结符放在一起）加入：

```
%type <str>		mysql_routine_body
```

在 `CreateFunctionStmt` 产生式组（约 11069 行起）中，为 `PROCEDURE` 与 `FUNCTION` 各增加一条 MySQL 分支。以 `PROCEDURE` 为例，在现有 `| CREATE opt_or_replace PROCEDURE func_name func_args_with_defaults opt_createfunc_opt_list opt_routine_body` 分支**之前**插入：

```
			| CREATE opt_or_replace PROCEDURE func_name func_args_with_defaults
			  opt_createfunc_opt_list mysql_routine_body
				{
					CreateFunctionStmt *n = makeNode(CreateFunctionStmt);
					n->is_procedure = true;
					n->replace = $2;
					n->funcname = $4;
					n->parameters = $5;
					n->returnType = NULL;
					n->options = lappend($6,
						makeDefElem("language",
									(Node *) makeString(pstrdup("plmysql")),
									@7));
					n->options = lappend(n->options,
						makeDefElem("as",
									(Node *) list_make1(makeString($7)),
									@7));
					n->sql_body = NULL;
					$$ = (Node *)n;
				}
```

`FUNCTION` 分支同理，插在现有 `| CREATE opt_or_replace FUNCTION func_name func_args_with_defaults RETURNS func_return opt_createfunc_opt_list opt_routine_body` 分支之前：

```
			| CREATE opt_or_replace FUNCTION func_name func_args_with_defaults
			  RETURNS func_return opt_createfunc_opt_list mysql_routine_body
				{
					CreateFunctionStmt *n = makeNode(CreateFunctionStmt);
					n->is_procedure = false;
					n->replace = $2;
					n->funcname = $4;
					n->parameters = $5;
					n->returnType = $7;
					n->options = lappend($8,
						makeDefElem("language",
									(Node *) makeString(pstrdup("plmysql")),
									@9));
					n->options = lappend(n->options,
						makeDefElem("as",
									(Node *) list_make1(makeString($9)),
									@9));
					n->sql_body = NULL;
					$$ = (Node *)n;
				}
```

符号编号对照：`$1`=CREATE、`$2`=opt_or_replace、`$3`=FUNCTION、`$4`=func_name、`$5`=func_args_with_defaults、`$6`=RETURNS、`$7`=func_return、`$8`=opt_createfunc_opt_list、`$9`=mysql_routine_body。

- [ ] **Step 6: 补测 IF() 函数形式**

在 `src/test/mysql/t/test_002_routine_body_capture.py` 的 `run()` 末尾追加：

```python
    # IF(expr,a,b) 函数调用不应被误判为开块
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t002_iffunc")
            cur.execute("CREATE PROCEDURE t002_iffunc() "
                        "BEGIN SELECT IF(1, 2, 3); END")
    out = cluster.psql("SELECT prosrc FROM pg_proc WHERE proname='t002_iffunc';")
    src = out.strip()
    assert src.upper().rstrip(";").endswith("END"), \
        "IF() miscounted as block opener: %r" % src
```

- [ ] **Step 7: 构建并运行测试确认通过**

```bash
cd /home/unvdb/pg_github/openHalo && make -j$(nproc) && make install && cd src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `3/3 passed`。

若 bison 报 shift/reduce 冲突，需调整 `mysql_routine_body` 与 `opt_routine_body` 的优先级——两者都可以在 `opt_createfunc_opt_list` 之后出现 `BEGIN_P`，冲突点在于 `BEGIN_P ATOMIC` 与裸 `BEGIN_P`。解决方式是把 `mysql_routine_body` 改为 `BEGIN_P` 后前瞻一个 token，非 `ATOMIC` 才走捕获路径。

- [ ] **Step 8: Commit**

```bash
git add src/backend/parser/mysql/mys_gram.y src/include/parser/mysql/mys_gramparse.h src/test/mysql/t/test_002_routine_body_capture.py
git commit -m "feat(plmysql): capture bare BEGIN...END routine body text in MySQL grammar"
```

---

### Task 4: plmysql 关键字表切换到 MySQL SQL/PSM

**Files:**
- Modify: `src/pl/plmysql/src/pl_reserved_kwlist.h`
- Modify: `src/pl/plmysql/src/pl_unreserved_kwlist.h`
- Test: `src/test/mysql/t/test_003_declare_set.py`（本任务只加关键字断言部分）

**Interfaces:**
- Consumes: Task 2 的 plmysql 骨架
- Produces: 词法层可识别 MySQL SQL/PSM 关键字 token（`K_DECLARE`、`K_LEAVE`、`K_ITERATE`、`K_REPEAT`、`K_UNTIL`、`K_ELSEIF`、`K_HANDLER`、`K_CONDITION`、`K_SIGNAL`、`K_RESIGNAL` 等），供 Task 5 的语法产生式使用

关键字表格式（`pl_reserved_kwlist.h` 现有条目形如 `PG_KEYWORD("begin", K_BEGIN)`），按字母序维护。

- [ ] **Step 1: 写失败测试**

创建 `src/test/mysql/t/test_003_declare_set.py`：

```python
"""MySQL SQL/PSM 局部变量声明与赋值。"""


def run(cluster):
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t003_p")
            cur.execute("""
                CREATE PROCEDURE t003_p()
                BEGIN
                    DECLARE v INT DEFAULT 1;
                    DECLARE w INT;
                    SET w = v + 41;
                    SELECT w;
                END
            """)
            cur.execute("CALL t003_p()")
            row = cur.fetchone()
            assert row == (42,), "expected (42,), got %r" % (row,)
```

> 这个测试要到 Task 5 才会变绿——Task 4 只提供词法层的关键字 token，语法产生式是 Task 5 的工作。本任务自身的验收标准是 Step 4 的关键字表生成检查。

- [ ] **Step 2: 运行测试确认失败**

Expected: `not ok - test_003_declare_set`，错误来自 plmysql 编译器（当前语法是克隆来的 plpgsql 结构，`DECLARE` 不能出现在 `BEGIN` 之后）。

- [ ] **Step 3: 增补 MySQL 保留关键字**

在 `src/pl/plmysql/src/pl_reserved_kwlist.h` 中按字母序插入以下条目（保留 plpgsql 原有的 `K_BEGIN`、`K_DECLARE`、`K_END`、`K_IF`、`K_ELSE`、`K_WHILE`、`K_LOOP`、`K_CASE`、`K_RETURN` 等已存在的同名条目，不重复添加）：

```c
PG_KEYWORD("condition", K_CONDITION)
PG_KEYWORD("elseif", K_ELSEIF)
PG_KEYWORD("handler", K_HANDLER)
PG_KEYWORD("iterate", K_ITERATE)
PG_KEYWORD("leave", K_LEAVE)
PG_KEYWORD("repeat", K_REPEAT)
PG_KEYWORD("resignal", K_RESIGNAL)
PG_KEYWORD("signal", K_SIGNAL)
PG_KEYWORD("until", K_UNTIL)
```

在 `src/pl/plmysql/src/pl_unreserved_kwlist.h` 中按字母序插入：

```c
PG_KEYWORD("do", K_DO)
PG_KEYWORD("sqlexception", K_SQLEXCEPTION)
PG_KEYWORD("sqlstate", K_SQLSTATE)
PG_KEYWORD("sqlwarning", K_SQLWARNING)
```

删除 plpgsql 特有、MySQL 不存在的保留字（避免与用户标识符冲突）：`K_ALIAS`、`K_ASSERT`、`K_PERFORM`、`K_RAISE`、`K_STRICT`。删除时必须同步删除 `pl_gram.y` 中所有引用这些 token 的产生式，否则 bison 报 undefined token。

> **实现者注意**：`K_ELSEIF` 与 plpgsql 已有的 `K_ELSIF` 是不同拼写。MySQL 用 `ELSEIF`（无空格），plpgsql 用 `ELSIF`/`ELSEIF` 两种都接受。保留 plpgsql 的 `K_ELSIF` 条目不会冲突，但 Task 5 的语法产生式应只使用 `K_ELSEIF`。

- [ ] **Step 4: 构建确认关键字表生成成功**

```bash
cd /home/unvdb/pg_github/openHalo/src/pl/plmysql/src && make clean && cd /home/unvdb/pg_github/openHalo && make -j$(nproc) 2>&1 | grep -i "error\|warning: .*token" | head
```

Expected: 无 error 输出。生成的 `pl_reserved_kwlist_d.h` 应包含新增关键字：

```bash
grep -c "condition\|elseif\|handler\|iterate\|leave\|repeat\|resignal\|signal\|until" /home/unvdb/pg_github/openHalo/src/pl/plmysql/src/pl_reserved_kwlist_d.h
```

Expected: 大于 0。

- [ ] **Step 5: Commit**

```bash
git add src/pl/plmysql/src/pl_reserved_kwlist.h src/pl/plmysql/src/pl_unreserved_kwlist.h src/pl/plmysql/src/pl_gram.y
git commit -m "feat(plmysql): switch keyword tables to MySQL SQL/PSM vocabulary"
```

---

### Task 5: plmysql 语法 — BEGIN...END 块、DECLARE 变量、SET 赋值

**Files:**
- Modify: `src/pl/plmysql/src/pl_gram.y`
- Modify: `src/pl/plmysql/src/pl_comp.c`（若块结构变化影响 `plmysql_compile` 的入口符号）
- Test: `src/test/mysql/t/test_003_declare_set.py`（Task 4 已创建，本任务追加断言）

**Interfaces:**
- Consumes: Task 4 的关键字 token（`K_DECLARE` 等）
- Produces:
  - `pl_block` 接受 MySQL 块结构：`[label] BEGIN <decl_stmts> <proc_sect> END [label]`
  - 新非终结符 `mysql_decl_sect`（`%type <declhdr>`）、`mysql_decl_stmts`、`mysql_decl_stmt`、`decl_varnames`（`%type <list>`，元素为 `String` 节点）、`stmt_set`（`%type <stmt>`）
  - `DECLARE` 出现在 `BEGIN` 之后（与克隆来的 `DECLARE ... BEGIN` 顺序相反），支持一条声明多个同类型变量
  - `SET var = expr` 归约为 `PLMySQL_stmt_assign`
  - `IF`/`ELSEIF`/`RETURN` 沿用克隆来的产生式，不新增

- [ ] **Step 1: 确认测试当前失败**

```bash
cd /home/unvdb/pg_github/openHalo/src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `not ok - test_003_declare_set`。

- [ ] **Step 2: 改写块结构产生式**

克隆得到的 `pl_gram.y` 现有结构（对应 plpgsql 原文，符号已改名）是：

```
pl_block		: decl_sect K_BEGIN proc_sect exception_sect K_END opt_label
decl_sect		: opt_block_label
				| opt_block_label decl_start
				| opt_block_label decl_start decl_stmts
decl_start		: K_DECLARE  { plmysql_add_initdatums(NULL);
			                   plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE; }
```

三个必须保持的既有机制（改写时不能丢）：

1. `opt_block_label` 的动作里有 `plmysql_ns_push(...)`，与 `pl_block` 末尾的 `plmysql_ns_pop()` 配对，丢失会导致命名空间栈失衡
2. `plmysql_IdentifierLookup` 在声明期间必须切到 `IDENTIFIER_LOOKUP_DECLARE`（避免扫描器把正在声明的名字当已有变量解析），声明结束切回 `IDENTIFIER_LOOKUP_NORMAL`
3. `plmysql_add_initdatums(&initvarnos)` 收集本块声明的变量编号，供块初始化使用

MySQL 结构是 `BEGIN` 在前、`DECLARE` 在块内且是独立语句。替换为：

```
pl_block		: opt_block_label K_BEGIN mysql_decl_sect proc_sect K_END opt_label
					{
						PLMySQL_stmt_block *new;

						new = palloc0(sizeof(PLMySQL_stmt_block));
						new->cmd_type	= PLMYSQL_STMT_BLOCK;
						new->lineno		= plmysql_location_to_lineno(@2);
						new->stmtid		= ++plmysql_curr_compile->nstatements;
						new->label		= $1;
						new->n_initvars = $3.n_initvars;
						new->initvarnos = $3.initvarnos;
						new->body		= $4;
						new->exceptions	= NULL;

						check_labels($1, $6, @6);
						plmysql_ns_pop();

						$$ = (PLMySQL_stmt *)new;
					}
				;

mysql_decl_sect	: /*EMPTY*/
					{
						$$.label	  = NULL;
						$$.n_initvars = 0;
						$$.initvarnos = NULL;
					}
				| mysql_decl_stmts
					{
						$$.label	  = NULL;
						$$.n_initvars = plmysql_add_initdatums(&($$.initvarnos));
					}
				;

mysql_decl_stmts: mysql_decl_stmts mysql_decl_stmt
				| mysql_decl_stmt
				;
```

注意 `$1` 是 `opt_block_label`（`%type <str>`），不是 `decl_sect`（`%type <declhdr>`），因此是 `$1` 而非 `$1.label`——克隆来的原产生式里 `$1` 指向 `decl_sect` 所以写作 `$1.label`，改写后位置变了，直接沿用会编译报错。

`%type` 声明区需要增加：

```
%type <declhdr> mysql_decl_sect
%type <list>    decl_varnames
%type <stmt>    stmt_set
```

并保留原有的 `%type <declhdr> decl_sect`（若 `decl_sect` 及其分支已无引用则一并删除，同时删除 `decl_start` 产生式）。

- [ ] **Step 3: 实现 DECLARE 语句（支持一条声明多个变量）**

MySQL 的 `DECLARE a, b, c INT DEFAULT 0;` 一条语句声明多个同类型变量，克隆来的 `decl_statement` 只支持单变量。新增产生式：

```
mysql_decl_stmt	: K_DECLARE
					{
						/*
						 * Suppress identifier resolution while the names being
						 * declared are scanned, then restore it in the trailing
						 * action.  MySQL allows DECLARE only at the head of a
						 * block, but each DECLARE is its own statement, so the
						 * toggle is per-statement rather than per-section.
						 */
						plmysql_add_initdatums(NULL);
						plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
					}
				  decl_varnames decl_datatype decl_defval ';'
					{
						ListCell   *lc;
						int			lno = plmysql_location_to_lineno(@1);

						plmysql_IdentifierLookup = IDENTIFIER_LOOKUP_NORMAL;

						foreach(lc, $3)
						{
							char			 *name = strVal(lfirst(lc));
							PLMySQL_variable *var;
							PLMySQL_type	 *typ;

							/*
							 * decl_datatype returns a freshly built struct that
							 * plmysql_build_variable takes ownership of, so each
							 * variable needs its own copy when one DECLARE names
							 * several.
							 */
							typ = palloc(sizeof(PLMySQL_type));
							memcpy(typ, $4, sizeof(PLMySQL_type));

							var = plmysql_build_variable(name, lno, typ, true);
							var->default_val = $5;
						}
					}
				;

decl_varnames	: decl_varname
					{
						$$ = list_make1(makeString($1.name));
					}
				| decl_varnames ',' decl_varname
					{
						$$ = lappend($1, makeString($3.name));
					}
				;
```

`decl_varname`、`decl_datatype`、`decl_defval` 三个非终结符直接沿用克隆来的定义，不改动。

> **实现者注意**：`decl_defval` 返回的 `PLMySQL_expr *` 在多变量场景下被多个变量共享。plpgsql 的执行器在块初始化时对每个变量独立求值同一个表达式，共享是安全的（表达式节点只读）。但若后续 M2 引入表达式级缓存，需要重新评估这一点。

- [ ] **Step 4: 增加 SET 赋值产生式**

plpgsql 的赋值语法是 `var := expr`（`stmt_assign`）。MySQL 用 `SET var = expr`。在 `proc_stmt` 的可选分支中增加：

```
stmt_set		: K_SET assign_var '=' expr ';'
					{
						PLMySQL_stmt_assign *new;

						new = palloc0(sizeof(PLMySQL_stmt_assign));
						new->cmd_type = PLMYSQL_STMT_ASSIGN;
						new->lineno   = plmysql_location_to_lineno(@1);
						new->stmtid   = ++plmysql_curr_compile->nstatements;
						new->varno    = $2->dno;
						new->expr     = $4;

						$$ = (PLMySQL_stmt *)new;
					}
				;
```

并在 `proc_stmt` 的分支列表中加入 `| stmt_set { $$ = $1; }`（`%type <stmt> stmt_set` 已在 Step 2 的类型声明中加过）。

MySQL 也支持 `SET a = 1, b = 2;` 多重赋值。本任务只实现单赋值形式，多重赋值留到 M2。

- [ ] **Step 5: 补测 IF / RETURN 继承自克隆是否可用**

spec 的 M1 目标含「`IF`/`RETURN` 可跑」。这两者不需要新写产生式——MySQL 的 `IF cond THEN ... ELSEIF ... ELSE ... END IF;` 与 `RETURN expr;` 和 plpgsql 语法一致（plpgsql 的 `K_ELSIF` 关键字表同时收录了 `elseif` 拼写），克隆后应直接可用。但必须验证 Step 2 的块结构改写没有破坏它们。

在 `src/test/mysql/t/test_003_declare_set.py` 的 `run()` 末尾追加：

```python
    # IF/ELSEIF/ELSE 继承自克隆，块结构改写后仍须可用
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t003_if")
            cur.execute("""
                CREATE PROCEDURE t003_if(n INT)
                BEGIN
                    DECLARE r TEXT;
                    IF n < 0 THEN
                        SET r = 'neg';
                    ELSEIF n = 0 THEN
                        SET r = 'zero';
                    ELSE
                        SET r = 'pos';
                    END IF;
                    SELECT r;
                END
            """)
            for arg, want in ((-1, 'neg'), (0, 'zero'), (1, 'pos')):
                cur.execute("CALL t003_if(%s)", (arg,))
                row = cur.fetchone()
                assert row == (want,), "n=%d: expected %r, got %r" % (arg, want, row)

    # RETURN（存储函数）继承自克隆
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("DROP FUNCTION IF EXISTS t003_f")
            cur.execute("""
                CREATE FUNCTION t003_f(n INT) RETURNS INT
                BEGIN
                    DECLARE d INT DEFAULT 10;
                    RETURN n * d;
                END
            """)
            cur.execute("SELECT t003_f(4)")
            row = cur.fetchone()
            assert row == (40,), "expected (40,), got %r" % (row,)

    # 一条 DECLARE 声明多个同类型变量
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t003_multi")
            cur.execute("""
                CREATE PROCEDURE t003_multi()
                BEGIN
                    DECLARE a, b, c INT DEFAULT 5;
                    SET a = a + b + c;
                    SELECT a;
                END
            """)
            cur.execute("CALL t003_multi()")
            row = cur.fetchone()
            assert row == (15,), "expected (15,), got %r" % (row,)
```

- [ ] **Step 6: 构建并运行测试确认通过**

```bash
cd /home/unvdb/pg_github/openHalo && make -j$(nproc) && make install && cd src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `4/4 passed`。

bison 冲突处理：`K_SET` 在克隆来的语法中未被使用，新增 `stmt_set` 本身不应产生冲突；块结构改写（`mysql_decl_sect` 可为空且 `proc_sect` 也可为空）是更可能的冲突源。若 `pl_gram.y` 顶部的 `%expect 0` 导致构建失败，必须实际消解冲突而不是提高 `%expect` 数值——用 `bison -Wcounterexamples` 定位冲突路径。

- [ ] **Step 7: Commit**

```bash
git add src/pl/plmysql/src/pl_gram.y src/pl/plmysql/src/pl_comp.c src/test/mysql/t/test_003_declare_set.py
git commit -m "feat(plmysql): implement MySQL block structure, DECLARE and SET"
```

---

### Task 6: 跨协议执行拒绝

**Files:**
- Modify: `src/pl/plmysql/src/pl_handler.c`
- Test: `src/test/mysql/t/test_004_protocol_scope.py`

**Interfaces:**
- Consumes: Task 2 的 `plmysql_call_handler`
- Produces: `plmysql_call_handler()` 在非 MySQL 协议会话下 `ereport(ERROR, ...)`；`plmysql_validator()` 不做协议检查（保 `pg_restore` 链路）

设计依据：spec §1「作用域」——创建期允许（保备份恢复），执行期拒绝。

- [ ] **Step 1: 写失败测试**

创建 `src/test/mysql/t/test_004_protocol_scope.py`：

```python
"""plmysql 例程只能在 MySQL 协议会话中执行；创建不受限。"""
import subprocess


def run(cluster):
    # 创建：PG 协议下必须成功（pg_restore 场景）
    cluster.psql("""
        CREATE FUNCTION t004_f() RETURNS int
        LANGUAGE plmysql AS $$ BEGIN RETURN 7; END $$;
    """)

    # 执行：PG 协议下必须报错
    try:
        cluster.psql("SELECT t004_f();")
        raise AssertionError("plmysql routine executed over PostgreSQL protocol")
    except subprocess.CalledProcessError as e:
        assert "MySQL protocol" in e.stderr, \
            "wrong error for cross-protocol call: %r" % e.stderr

    # 执行：MySQL 协议下必须成功
    with cluster.mysql() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t004_f()")
            row = cur.fetchone()
            assert row == (7,), "expected (7,), got %r" % (row,)
```

- [ ] **Step 2: 运行测试确认失败**

Expected: `not ok - test_004_protocol_scope`，断言信息 `plmysql routine executed over PostgreSQL protocol`。

- [ ] **Step 3: 在 call handler 加协议检查**

修改 `src/pl/plmysql/src/pl_handler.c`。在文件顶部 include 区加入：

```c
#include "libpq/libpq-be.h"
#include "miscadmin.h"
#include "nodes/nodes.h"
```

在 `plmysql_call_handler(PG_FUNCTION_ARGS)` 函数体最开头（进入任何编译/执行逻辑之前）插入：

```c
	/*
	 * plmysql routines carry MySQL dialect semantics that only hold when the
	 * MySQL parser and executor engines are active, which InitParserEngine()
	 * and InitExecutorEngine() only select for MySQL-protocol sessions.  Refuse
	 * to run rather than silently misinterpret the body.
	 *
	 * The validator deliberately does NOT perform this check: pg_restore and
	 * logical replication replay DDL over the PostgreSQL protocol, and blocking
	 * creation there would break backup/restore.
	 */
	if (MyProcPort == NULL ||
		nodeTag(MyProcPort->protocol_handler) != T_MySQLProtocol)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("plmysql routines can only be executed over the MySQL protocol"),
				 errhint("Connect to the MySQL listener port instead of the PostgreSQL port.")));
```

- [ ] **Step 4: 构建并运行测试确认通过**

```bash
cd /home/unvdb/pg_github/openHalo && make -j$(nproc) && make install && cd src/test/mysql && python3 run_tests.py /home/unvdb/pg_github/openHalo/tmp_install/bin
```

Expected: `5/5 passed`。

- [ ] **Step 5: 验证 M1 目标场景端到端可用**

```bash
cd /home/unvdb/pg_github/openHalo/tmp_install/bin && ./psql -h 127.0.0.1 -p 55432 -c "SELECT 1" >/dev/null && mysql -h 127.0.0.1 -P 53306 -u halo -e "
CREATE PROCEDURE m1_demo() BEGIN DECLARE v INT DEFAULT 1; SET v = v + 41; SELECT v; END;
CALL m1_demo();"
```

Expected: 输出一行 `42`。

（此步依赖测试集群处于运行状态；若已被 teardown，改用 `run_tests.py` 的等价断言。）

- [ ] **Step 6: Commit**

```bash
git add src/pl/plmysql/src/pl_handler.c src/test/mysql/t/test_004_protocol_scope.py
git commit -m "feat(plmysql): reject routine execution outside MySQL protocol sessions"
```

---

## M1 完成标准

- `make check -C src/test/mysql` 全绿（5 个测试文件）
- MySQL 协议下 `CREATE PROCEDURE p() BEGIN DECLARE v INT DEFAULT 1; SET v = v + 41; SELECT v; END;` + `CALL p()` 返回 42
- 对标 spec §M1 的四项语法可用：`DECLARE`（含一条声明多变量）、`SET` 赋值、`IF/ELSEIF/ELSE/END IF`、`RETURN`（存储函数）
- `pg_proc.prolang` 指向 `plmysql`，`prosrc` 存原始过程体文本（含 `BEGIN`/`END`）
- 嵌套 `BEGIN...END` 与 `IF(a,b,c)` 函数调用形式均不导致过程体截断
- PostgreSQL 协议下调用 plmysql 例程报错，但创建成功（`pg_restore` 链路可用）
- `src/pl/plpgsql/` 零改动：`git diff --stat src/pl/plpgsql/` 输出为空
- `AUTO_INCREMENT` 触发器链路未受影响：MySQL 协议下建一张带 `AUTO_INCREMENT` 的表、插入两行、确认自增列为 1 和 2

## 后续计划（不在本计划范围）

| 计划 | 内容 | 依赖 |
|---|---|---|
| M2 | 流程控制：`IF/ELSEIF`、`CASE`、`WHILE`、`LOOP`、`REPEAT`、`LEAVE`、`ITERATE`、多重 `SET` | M1 |
| M3 | 游标：`DECLARE CURSOR`/`OPEN`/`FETCH`/`CLOSE` + EXIT HANDLER | M2 |
| M4 | CONTINUE HANDLER、`SIGNAL`/`RESIGNAL`、`GET DIAGNOSTICS`、错误码表修复与扩充 | M3 |
| M5 | `CALL` OUT/INOUT 回写、多结果集协议打通 | M1（可与 M2-M4 并行） |
| M6 | 元数据视图修正、`DEFINER`/`COMMENT` 语法、`DETERMINISTIC` 映射修正、触发器入口预留 | M1 |

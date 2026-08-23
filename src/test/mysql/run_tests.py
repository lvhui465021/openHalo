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
    try:
        cluster.setup()
    except Exception:
        # setup() can fail after pg_ctl start already succeeded (e.g. the
        # CREATE EXTENSION at the end of setup() errors out). Without this,
        # the postmaster it started leaks and holds mysql_port/pg_port,
        # breaking every subsequent run until manually killed.
        cluster.teardown()
        raise
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

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
        env["PGUSER"] = "halo"
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

    def psql(self, sql, dbname="halo0root"):
        r = self._run([self._bin("psql"), "-X", "-q", "-A", "-t",
                       "-v", "ON_ERROR_STOP=1", "-d", dbname, "-c", sql])
        return r.stdout

    def mysql(self, dbname=None):
        return pymysql.connect(host="127.0.0.1", port=self.mysql_port,
                               user="halo", database=dbname,
                               autocommit=True, charset="utf8mb4")

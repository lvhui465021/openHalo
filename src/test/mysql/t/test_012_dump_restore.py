"""pg_dump / pg_restore round-trip for plmysql routines: a routine created
over the MySQL protocol dumps, restores into a fresh database (over the
PostgreSQL protocol, where creation is allowed but execution is not), and
executes over the MySQL protocol afterwards.
"""
import os
import subprocess


def run(cluster):
    bin_ = cluster._bin
    db1, db2 = "halo0root", "t012_restore"
    _sql = cluster.psql

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("DROP PROCEDURE IF EXISTS t012_p")
            cur.execute("DROP FUNCTION IF EXISTS t012_f")
            cur.execute("CREATE TABLE t012_t(v INT)")
            cur.execute("INSERT INTO t012_t VALUES (1)")
            cur.execute("""CREATE PROCEDURE t012_p(OUT x INT)
                BEGIN DECLARE v INT; SELECT max(v) INTO v FROM t012_t;
                SET x = v; END""")
            cur.execute("""CREATE FUNCTION t012_f() RETURNS INT
                BEGIN DECLARE v INT; SELECT max(v) INTO v FROM t012_t;
                RETURN v; END""")

    # dump both databases (routines + data)
    dump1 = os.path.join(cluster.basedir, "t012_dump1.sql")
    env = dict(os.environ, PGHOST=cluster.sockdir, PGPORT=str(cluster.pg_port),
               PGUSER="halo")
    with open(dump1, "w") as f:
        subprocess.run([bin_("pg_dump"), "-d", db1], stdout=f, env=env,
                       check=True)

    _sql("CREATE DATABASE " + db2)
    with open(dump1) as f:
        subprocess.run([bin_("psql"), "-X", "-q", "-v", "ON_ERROR_STOP=1",
                        "-d", db2, "-f", dump1], env=env, check=True)

    # the routine exists in the restored database and runs over MySQL
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT t012_f()")
            assert cur.fetchone() == (1,)
            cur.execute("SET @x = 0")
            cur.execute("CALL t012_p(@x)")
            cur.execute("SELECT @x")
            assert cur.fetchone() == ("1",)

    # execution still refuses over the PostgreSQL protocol
    try:
        _sql("SELECT t012_f();")
        raise AssertionError("plmysql routine ran over PG protocol after restore")
    except subprocess.CalledProcessError as e:
        assert "MySQL protocol" in e.stderr

    _sql("DROP DATABASE " + db2)

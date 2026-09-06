"""Corpus environment parity: @@default_storage_engine and @@identity.

mysql-test-run starts the server with --default-storage-engine=MyISAM,
so MySQL 5.7 .result files show MyISAM as the default engine and expect
@@default_storage_engine echoed in canonical engine case (InnoDB,
MyISAM, MEMORY, ...) no matter how the SET spelled it.  aux_mysql 1.16
aligns the registry default, and the mys SET rectifier canonicalizes
known engine names (unknown names pass through unchanged -- MySQL would
raise ER_UNKNOWN_STORAGE_ENGINE there, we stay lenient).  The engine
name itself stays cosmetic: openHalo relations do not map to engines.

aux_mysql 1.16 also registers @@identity (MySQL's LAST_INSERT_ID
synonym, used by variables.test) as a plain writable session variable
so the name resolves at top level and in bodies; the LAST_INSERT_ID
read semantics are deliberately not implemented.
"""


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            # Fresh session default, per the mysql-test-run environment.
            cur.execute("SELECT @@default_storage_engine")
            assert cur.fetchone() == ('MyISAM',), cur.fetchall()

            # SET value is canonicalized however it was spelled.
            cur.execute("SET default_storage_engine='innodb'")
            cur.execute("SELECT @@default_storage_engine")
            assert cur.fetchone() == ('InnoDB',), cur.fetchall()

            cur.execute("SET @@default_storage_engine=MEMORY")
            cur.execute("SELECT @@default_storage_engine")
            assert cur.fetchone() == ('MEMORY',), cur.fetchall()

            # leave the default as found for any test that runs after this
            cur.execute("SET default_storage_engine=MyISAM")

            # @@identity resolves and is writable (plain session variable).
            cur.execute("SET @@identity = 42")
            cur.execute("SELECT @@identity")
            assert cur.fetchone() == ('42',), cur.fetchall()

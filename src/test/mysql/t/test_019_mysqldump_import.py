"""mysqldump-format DDL imports directly, including trigger sections.

mysqldump wraps statements in version-conditional comments (the server
executes the content when its own version is at least the gate) and emits
triggers under DELIMITER ;; with the CREATE DEFINER and TRIGGER keywords
split across separate comment blocks.  The kernel now lexes those comments
like MySQL 5.7 does, so a dump feeds through convert_mysqldump_file.py
(which only reorders foreign keys and passes trigger DDL through untouched)
and imports verbatim over the MySQL protocol.

The test acts as the mysql CLI would: honour DELIMITER directives, split on
the active delimiter, and send each statement as its own COM_QUERY.
"""
import os
import subprocess
import tempfile

import pymysql


DUMP = """\
-- MySQL dump 10.13  Distrib 5.7.42
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8mb4 */;
DROP TABLE IF EXISTS `t019_src`;
DROP TABLE IF EXISTS `t019_log`;
CREATE TABLE `t019_src` (
  `id` int(11) NOT NULL,
  `val` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE `t019_log` (
  `tag` varchar(16) DEFAULT NULL,
  `src_id` int(11) DEFAULT NULL,
  KEY `t019_log_src` (`src_id`),
  CONSTRAINT `t019_fk` FOREIGN KEY (`src_id`) REFERENCES `t019_src` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
/*!80016 CREATE TABLE `t019_future` (id int) */;
DELIMITER ;;
/*!50003 SET SESSION SQL_MODE="" */;;
/*!50003 CREATE*/ /*!50017 DEFINER=`halo`@`localhost`*/ /*!50003 TRIGGER `t019_trg_compound` AFTER INSERT ON `t019_src`
FOR EACH ROW BEGIN
INSERT INTO `t019_log` (`tag`, `src_id`) VALUES ('compound', NEW.id);
INSERT INTO `t019_log` (`tag`, `src_id`) VALUES ('compound2', NEW.id);
END */;;
/*!50003 CREATE*/ /*!50017 DEFINER=`halo`@`localhost`*/ /*!50003 TRIGGER `t019_trg_single` BEFORE UPDATE ON `t019_src` FOR EACH ROW SET NEW.val = NEW.val + 1 */;;
DELIMITER ;
"""


def _split_client_statements(text):
    """Split a dump the way the mysql CLI does: DELIMITER switches the
    statement terminator, which is otherwise ';'.  Lines accumulate until one
    ends with the active terminator; the terminator itself is dropped."""
    statements = []
    delimiter = ";"
    pending = []
    for line in text.splitlines():
        stripped = line.strip().lower()
        if stripped.startswith("delimiter "):
            if pending:
                statements.append("\n".join(pending))
                pending = []
            delimiter = stripped.split()[1]
            continue
        pending.append(line)
        if line.rstrip().endswith(delimiter):
            statement = "\n".join(pending)
            statements.append(statement[:statement.rindex(delimiter)])
            pending = []
    if pending:
        statements.append("\n".join(pending))
    return statements


def run(cluster):
    tmpdir = tempfile.mkdtemp(prefix="t019_")
    dump_path = os.path.join(tmpdir, "t019_dump.sql")

    with open(dump_path, "w") as fh:
        fh.write(DUMP)

    # The converter must keep the trigger DDL verbatim (it exists to reorder
    # foreign keys, which the dump above exercises with t019_fk).
    subprocess.run(
        ["python3",
         os.path.join(os.path.dirname(__file__), "..", "..", "..", "..",
                      "tools", "convert_mysqldump_file.py"),
         dump_path],
        check=True, capture_output=True)

    converted_path = os.path.join(tmpdir, "converted_t019_dump.sql")
    with open(converted_path) as fh:
        converted = fh.read()
    assert "CREATE TRIGGER" not in converted.replace("CREATE*/", "CREATE "), \
        "converter must not rewrite mysqldump trigger DDL"
    assert "TRIGGER `t019_trg_compound`" in converted, \
        "trigger DDL was dropped by the converter"
    assert "ALTER TABLE t019_log ADD CONSTRAINT `t019_fk`" in converted, \
        "foreign key was not deferred by the converter"

    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for statement in _split_client_statements(converted):
                if statement.strip():
                    cur.execute(statement)

            cur.execute("INSERT INTO t019_src (id, val) VALUES (1, 10)")
            cur.execute("UPDATE t019_src SET val = 20 WHERE id = 1")

            cur.execute(
                "SELECT tag, count(*) FROM t019_log GROUP BY tag ORDER BY tag")
            assert cur.fetchall() == (("compound", 1), ("compound2", 1)), \
                "compound trigger body from the dump did not fire"
            cur.execute("SELECT val FROM t019_src WHERE id = 1")
            assert cur.fetchone() == (21,), \
                "single-statement trigger body from the dump did not fire"

            cur.execute("SHOW CREATE TRIGGER t019_trg_single")
            show = cur.fetchone()
            assert "SET NEW.val = NEW.val + 1" in show[2], \
                "original single-statement body was not preserved: %r" % (show[2],)
            assert "*/" not in show[2], \
                "executable-comment terminator leaked into the stored body"

            # The 80016 gate is above the implemented MySQL 5.7 level, so the
            # statement it wraps was skipped, not executed.
            cur.execute(
                "SELECT count(*) FROM information_schema.tables "
                "WHERE table_name = 't019_future'")
            assert cur.fetchone() == (0,), \
                "a version-gated statement above 5.7 was executed"

    # The FK deferred by the converter is NOT VALID, so it exists as a
    # constraint despite the child rows written before validation.
    out = cluster.psql("""
        SELECT count(*) FROM pg_constraint
        WHERE conname = 't019_fk' AND convalidated = false;""")
    assert out.strip() == "1", "deferred foreign key was not created NOT VALID"

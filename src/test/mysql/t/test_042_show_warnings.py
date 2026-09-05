"""MySQL 5.7 diagnostics area: SHOW WARNINGS / SHOW ERRORS / SHOW COUNT(*).

Covers the semantics MySQL documents for the per-statement condition list
(WL#5928, verified against mysql-test/r/wl5928.result and warnings.result):

  * SHOW WARNINGS lists every stored condition (Error + Warning + Note),
    SHOW ERRORS only the Error rows, in the order they were raised;
  * SHOW COUNT(*) WARNINGS/ERRORS return a scalar one-column result set
    (@@session.warning_count / @@session.error_count) with exactly one
    row, counting Error rows in warning_count as well;
  * the diagnostics statements themselves do NOT clear the area, every
    ordinary statement does (at its start, so its own parse/execution
    conditions are retained);
  * a failed statement leaves its Error condition behind for SHOW ERRORS.

openHalo side (adapter.c): Warning/Note conditions are captured through
emit_log_hook as the backend reports them, Error conditions are appended
by sendErrPacket() once the final MySQL errno is known (converting any
earlier would consume a pending SIGNAL MYSQL_ERRNO), and the clear happens
at the top of processCommand() -- the single funnel for COM_QUERY /
COM_STMT_EXECUTE -- with mysDiagStmtKind() exempting the diagnostics
statements.  The OK/EOF packet warning_count is stamped from the same
queue.

Two condition sources are reachable from the MySQL protocol with a plain
client and therefore pin the behavior end to end:

  * parse-time WARNING: CREATE GLOBAL TEMPORARY TABLE makes mys_gram.y's
    OptTemp rule emit "GLOBAL is deprecated in temporary table creation"
    (this is also the case the earlier implementation lost, because the
    clear used to sit between parse and execution);
  * execution-time ERROR: DROP TABLE of a missing table.
"""


def _rows(cur, sql):
    cur.execute(sql)
    return [tuple(r) for r in cur.fetchall()]


def _assert(cond, msg):
    if not cond:
        raise AssertionError(msg)


def run(cluster):
    with cluster.mysql(dbname="public") as conn:
        cur = conn.cursor()

        # -- clean start: ordinary statement leaves an empty area ----------
        cur.execute("SELECT 1")
        _assert(_rows(cur, "SHOW WARNINGS") == [], "expected empty SHOW WARNINGS")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(0,)],
                "warning_count should be 0 after a clean statement")
        _assert(_rows(cur, "SHOW COUNT(*) ERRORS") == [(0,)],
                "error_count should be 0 after a clean statement")

        # -- a failed statement leaves its Error condition behind ----------
        try:
            cur.execute("DROP TABLE t042_no_such_table")
            _assert(False, "DROP TABLE of missing table should have failed")
        except Exception:
            pass
        sw = _rows(cur, "SHOW WARNINGS")
        _assert(len(sw) == 1 and sw[0][0] == "Error",
                "SHOW WARNINGS should show the Error row, got %r" % (sw,))
        _assert(isinstance(sw[0][1], int) and sw[0][1] > 0,
                "Error row Code should be a positive MySQL errno, got %r" % (sw,))
        se = _rows(cur, "SHOW ERRORS")
        _assert(se == sw, "SHOW ERRORS should equal the Error rows: %r vs %r"
                % (se, sw))
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(1,)],
                "warning_count counts Error rows too (wl5928)")
        _assert(_rows(cur, "SHOW COUNT(*) ERRORS") == [(1,)],
                "error_count should be 1 after a failed statement")

        # -- the next ordinary statement clears the area --------------------
        cur.execute("SELECT 1")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(0,)],
                "ordinary statement must clear the diagnostics area")

        # -- parse-time warnings are retained (clear precedes parsing) -----
        cur.execute("DROP TABLE IF EXISTS t042_gt")
        cur.execute("CREATE GLOBAL TEMPORARY TABLE t042_gt (a int)")
        sw = _rows(cur, "SHOW WARNINGS")
        _assert(len(sw) == 1 and sw[0][0] == "Warning"
                and "GLOBAL is deprecated" in sw[0][2],
                "parse-time WARNING should be retained, got %r" % (sw,))
        _assert(_rows(cur, "SHOW ERRORS") == [],
                "a WARNING must not appear in SHOW ERRORS")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(1,)],
                "warning_count should be 1 after the parse warning")
        _assert(_rows(cur, "SHOW COUNT(*) ERRORS") == [(0,)],
                "error_count should stay 0 for a pure warning")

        # -- the diagnostics statements themselves keep the area intact ----
        _rows(cur, "SHOW WARNINGS")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(1,)],
                "SHOW WARNINGS must not clear the diagnostics area")
        _rows(cur, "SHOW COUNT(*) ERRORS")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(1,)],
                "SHOW COUNT(*) must not clear the diagnostics area")
        cur.execute("SELECT 1")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(0,)],
                "ordinary statement must clear again")

        # -- result-set shapes ----------------------------------------------
        cur.execute("SHOW WARNINGS")
        _assert([d[0] for d in cur.description] == ["Level", "Code", "Message"],
                "SHOW WARNINGS column names, got %r"
                % ([d[0] for d in cur.description],))
        cur.execute("CREATE GLOBAL TEMPORARY TABLE t042_gt2 (a int)")
        cur.execute("SHOW COUNT(*) WARNINGS")
        _assert([d[0] for d in cur.description] == ["@@session.warning_count"],
                "SHOW COUNT(*) WARNINGS column name, got %r"
                % ([d[0] for d in cur.description],))
        _assert([tuple(r) for r in cur.fetchall()] == [(1,)],
                "SHOW COUNT(*) WARNINGS always returns one row")
        try:
            cur.execute("DROP TABLE t042_no_such_table")
        except Exception:
            pass
        cur.execute("SHOW COUNT(*) ERRORS")
        _assert([d[0] for d in cur.description] == ["@@session.error_count"],
                "SHOW COUNT(*) ERRORS column name, got %r"
                % ([d[0] for d in cur.description],))
        _assert([tuple(r) for r in cur.fetchall()] == [(1,)],
                "SHOW COUNT(*) ERRORS always returns one row")
        cur.execute("SELECT 1")

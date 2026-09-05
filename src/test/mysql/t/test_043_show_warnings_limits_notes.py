"""SHOW WARNINGS leftovers round: LIMIT clause, MySQL Note rows, errno fixes.

Covers the second round of diagnostics-area compatibility work:

  * SHOW WARNINGS [LIMIT [offset,] count] / SHOW ERRORS [LIMIT ...]
    (MySQL 5.7 grammar; LIMIT applies to the displayed condition rows);
  * CREATE TABLE IF NOT EXISTS on an existing table records MySQL's
    Note 1050 (ER_TABLE_EXISTS_ERROR) in the diagnostics area -- the
    backend raises it as a WARNING because NOTICE-level reports never
    reach the capture hook under client_min_messages=error, and the
    adapter demotes errno 1050 back to "Note" like MySQL does;
  * SET sql_mode that flips NO_AUTO_CREATE_USER in either direction
    records Warning 3090 (ER_WARN_DEPRECATED_SQLMODE, MySQL 5.7);
  * adapter error packets that pick a concrete MySQL errno (1049 etc.)
    no longer get re-mapped to the generic 1105 by convertErrorCode().
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

        # -- setup: one stored condition (the area resets per statement, so a
        # second duplicate create replaces the first note -- MySQL 5.7 keeps
        # only the current statement's conditions) --------------------------
        cur.execute("DROP TABLE IF EXISTS t043_dup")
        cur.execute("CREATE TABLE t043_dup (a int)")
        cur.execute("CREATE TABLE IF NOT EXISTS t043_dup (a int)")   # Note 1050
        cur.execute("CREATE TABLE IF NOT EXISTS t043_dup (a int)")   # again
        sw = _rows(cur, "SHOW WARNINGS")
        _assert(len(sw) == 1 and sw[0][0] == "Note" and sw[0][1] == 1050,
                "duplicate CREATE TABLE IF NOT EXISTS should record one "
                "Note 1050 for the current statement, got %r" % (sw,))

        # -- SHOW WARNINGS LIMIT -------------------------------------------
        _assert(_rows(cur, "SHOW WARNINGS LIMIT 1") == sw,
                "LIMIT 1 should keep the single row")
        _assert(_rows(cur, "SHOW WARNINGS LIMIT 0") == [],
                "LIMIT 0 should return no rows")
        _assert(_rows(cur, "SHOW WARNINGS LIMIT 10") == sw,
                "LIMIT 10 should keep the row")
        _assert(_rows(cur, "SHOW WARNINGS LIMIT 1, 1") == [],
                "LIMIT 1, 1 past the end should return no rows")
        _assert(_rows(cur, "SHOW ERRORS LIMIT 5") == [],
                "SHOW ERRORS with only Notes stays empty")
        # diagnostics statements still do not clear the area
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(1,)],
                "area must survive the LIMIT forms")
        cur.execute("SELECT 1")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(0,)],
                "an ordinary statement clears the area again")

        # -- sql_mode 3090 on NO_AUTO_CREATE_USER flip ----------------------
        # (robust against whatever mode the session starts with: force the
        # flag on, then flip it off/on and require the deprecation warning
        # for each direction, and none for an identical re-assignment)
        cur.execute("SET sql_mode = 'STRICT_TRANS_TABLES,NO_AUTO_CREATE_USER'")
        cur.execute("SELECT 1")            # drop any warning from the SET above
        cur.execute("SET sql_mode = 'STRICT_TRANS_TABLES'")
        sw = _rows(cur, "SHOW WARNINGS")
        _assert(len(sw) == 1 and sw[0][0] == "Warning" and sw[0][1] == 3090
                and "NO_AUTO_CREATE_USER" in sw[0][2],
                "removing NO_AUTO_CREATE_USER should record Warning 3090, "
                "got %r" % (sw,))
        cur.execute("SET sql_mode = 'STRICT_TRANS_TABLES,NO_AUTO_CREATE_USER'")
        sw = _rows(cur, "SHOW WARNINGS")
        _assert(len(sw) == 1 and sw[0][1] == 3090,
                "adding NO_AUTO_CREATE_USER back should warn too, got %r"
                % (sw,))
        cur.execute("SET sql_mode = 'STRICT_TRANS_TABLES,NO_AUTO_CREATE_USER'")
        _assert(_rows(cur, "SHOW COUNT(*) WARNINGS") == [(0,)],
                "unchanged sql_mode must not warn")
        cur.execute("SET sql_mode = ''")
        cur.execute("SELECT 1")

        # -- direct errno call sites are no longer remapped to 1105 ---------
        try:
            cur.execute("ALTER DATABASE public SET x = 1")
            _assert(False, "ALTER DATABASE should have been rejected")
        except Exception as e:
            _assert(getattr(e, "args", (None,))[0] == 1049,
                    "ALTER DATABASE rejection should carry MySQL errno 1049, "
                    "got %r" % (getattr(e, "args", None),))
        _assert(_rows(cur, "SHOW COUNT(*) ERRORS") == [(1,)],
                "the 1049 error should be in the diagnostics area")
        se = _rows(cur, "SHOW ERRORS LIMIT 1")
        _assert(len(se) == 1 and se[0][0] == "Error" and se[0][1] == 1049,
                "SHOW ERRORS LIMIT 1 should show the 1049 Error, got %r"
                % (se,))
        cur.execute("SELECT 1")

        cur.execute("DROP TABLE IF EXISTS t043_dup")

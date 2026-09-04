/*
 * aux_mysql 1.10 -> 1.11
 *
 * A regular (non-trigger) plmysql routine's own metadata -- definer,
 * sql_mode snapshot, created / last_altered timestamps, sql_data_access --
 * used to be recorded in pg_proc.proconfig, alongside a MySQL trigger's
 * (which still is: see mys_make_mysql_trigger_function(), mys_utility.c).
 * PostgreSQL's own ExecuteCallStmt() treats any non-empty proconfig as
 * reason to force a CALL of the routine into an atomic execution context,
 * unconditionally rejecting COMMIT/ROLLBACK in its body regardless of SQL
 * SECURITY -- this was the actual root cause of the compat report's C2 gap,
 * not a missing "atomic=false" flag as first guessed.
 *
 * mys_utility.c now attaches that same metadata to the routine's OID as a
 * "plmysql" security label instead (SetSecurityLabel(), still dumped and
 * restored by pg_dump/pg_restore like proconfig was, as a
 * SECURITY LABEL FOR plmysql ON FUNCTION/PROCEDURE ... IS '...' statement),
 * leaving proconfig empty so CALL can run non-atomically.  Point
 * mysql.get_plmysql_config() -- the single choke point every consumer
 * (get_proc_def, get_func_def, mys_informa_schema.functions/procedures/
 * routines, mysql.proc, show_create_function, show_create_procedure) already
 * goes through -- at the label first, falling back to proconfig unchanged
 * for anything the label doesn't have: a MySQL trigger's underlying
 * function (still proconfig-only; a trigger is never dispatched through
 * CALL's atomic/non-atomic machinery, so proconfig's side effect never
 * applied to it and there was no reason to move it), and any routine
 * created before this version (a rolling upgrade, or restored from an older
 * dump) that only ever had proconfig to begin with.
 */

CREATE OR REPLACE FUNCTION mysql.get_plmysql_config(routineOid pg_catalog.oid,
                                                    confName pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
DECLARE
    label pg_catalog.text;
    ret pg_catalog.text;
    conf pg_catalog.text[];
BEGIN
    SELECT sl.label INTO label
    FROM pg_catalog.pg_seclabel sl
    WHERE sl.objoid = routineOid
      AND sl.classoid = 'pg_catalog.pg_proc'::pg_catalog.regclass
      AND sl.objsubid = 0
      AND sl.provider = 'plmysql';

    IF label IS NOT NULL THEN
        SELECT substring(item from position('=' in item) + 1) INTO ret
        FROM unnest(pg_catalog.string_to_array(label, chr(10))) AS item
        WHERE item LIKE pg_catalog.concat(confName, '=%')
        LIMIT 1;
        IF ret IS NOT NULL THEN
            RETURN ret;
        END IF;
    END IF;

    -- Fall back to the pre-1.11 storage: a MySQL trigger's private
    -- function (always), or a routine created before this version.
    SELECT proconfig INTO conf FROM pg_catalog.pg_proc WHERE oid = routineOid;
    IF conf IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT substring(item from position('=' in item) + 1) INTO ret
    FROM unnest(conf) AS item
    WHERE item LIKE pg_catalog.concat(confName, '=%')
    LIMIT 1;
    RETURN ret;
END
$$
STABLE LANGUAGE plpgsql;

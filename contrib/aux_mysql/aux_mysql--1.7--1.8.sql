/*
 * aux_mysql 1.7 -> 1.8
 *
 * Surface routine metadata that pg_proc cannot carry, as recorded by the
 * plmysql engine at CREATE time: the DEFINER account (user@host), the
 * sql_mode snapshot and the created / last-altered timestamps.  plmysql
 * stores them as function-local GUC settings in pg_proc.proconfig
 * (plmysql.definer / plmysql.sql_mode / plmysql.created /
 * plmysql.last_altered), so pg_dump/pg_restore and logical replication carry
 * them along with prosrc.  Routines created outside the MySQL protocol path
 * (e.g. pg_restore before this release) have no such settings and the views
 * fall back to their previous display values.
 *
 * ROUTINE_BODY and mysql.proc.language deliberately remain SQL: those are
 * the values specified by MySQL for stored routines, independent of the
 * implementation language used internally by openHalo.
 */

/*
 * Read one plmysql.* metadata GUC from a routine's proconfig; NULL when the
 * routine was created without one (or the name is absent).  Named parameters
 * are mandatory here: inside a PL/pgSQL-managed query a bare $2 positional
 * reference has no type to resolve until the operator context is too late,
 * and `$2 || '=%'` then gets inferred as boolean.
 */
CREATE OR REPLACE FUNCTION mysql.get_plmysql_config(routineOid pg_catalog.oid,
                                                    confName pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
DECLARE
    conf pg_catalog.text[];
    ret pg_catalog.text;
BEGIN
    SELECT proconfig INTO conf FROM pg_catalog.pg_proc WHERE oid = routineOid;
    if (conf is null) then
        return null;
    end if;
    SELECT substring(item from position('=' in item) + 1) INTO ret
    FROM unnest(conf) AS item
    WHERE item LIKE pg_catalog.concat(confName, '=%')
    LIMIT 1;
    return ret;
END
$$
STABLE LANGUAGE plpgsql;

/*
 * The SHOW CREATE formatters now take the pg_proc oid so they can render the
 * DEFINER account recorded at CREATE time; drop the old signatures together
 * with the views that reference them before rebuilding both.
 */
DROP VIEW IF EXISTS mys_informa_schema.functions;
DROP VIEW IF EXISTS mys_informa_schema.procedures;
DROP FUNCTION IF EXISTS mysql.get_proc_def(pg_catalog.text, pg_catalog.text,
                                           pg_catalog.oidvector,
                                           pg_catalog.oid[], "char"[],
                                           pg_catalog.text[], pg_catalog.text)
CASCADE;
DROP FUNCTION IF EXISTS mysql.get_func_def(pg_catalog.text, pg_catalog.text,
                                           pg_catalog.oid,
                                           pg_catalog.oidvector,
                                           pg_catalog.text[],
                                           pg_catalog.text)
CASCADE;

CREATE OR REPLACE FUNCTION mysql.get_proc_def(procName pg_catalog.text,
                                                procOwner pg_catalog.text,
                                                proargtypes pg_catalog.oidvector,
                                                proallargtypes pg_catalog.oid[],
                                                proargmodes "char"[],
                                                proargnames pg_catalog.text[],
                                                prosrc pg_catalog.text,
                                                procOid pg_catalog.oid)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    allArgNum pg_catalog.int4;
    argIndex pg_catalog.int4;
    argTypes pg_catalog.int4[];
    definerVal pg_catalog.text;
    definerUser pg_catalog.text;
    definerHost pg_catalog.text;
    atPos pg_catalog.int4;
BEGIN
    definerVal := coalesce(mysql.get_plmysql_config($8, 'plmysql.definer'),
                           pg_catalog.concat($2, '@%'));
    atPos := pg_catalog.strpos(definerVal, '@');
    if (atPos > 0) then
        definerUser := pg_catalog.substr(definerVal, 1, atPos - 1);
        definerHost := pg_catalog.substr(definerVal, atPos + 1);
    else
        definerUser := definerVal;
        definerHost := '%';
    end if;

    ret := 'CREATE DEFINER=`';
    ret := pg_catalog.concat(ret, definerUser);
    ret := pg_catalog.concat(ret, '`@`');
    ret := pg_catalog.concat(ret, definerHost);
    ret := pg_catalog.concat(ret, '` PROCEDURE `');
    ret := pg_catalog.concat(ret, procName);
    ret := pg_catalog.concat(ret, '`(');
    if (proallargtypes is not null) then
        allArgNum := array_length(proallargtypes, 1);
        argIndex := 1;
        LOOP
            if (1 < argIndex) then
                ret := pg_catalog.concat(ret, ', ');
            end if;

            if (proargmodes[argIndex] = 'i') then
                ret := pg_catalog.concat(ret, 'IN');
            elsif (proargmodes[argIndex] = 'b') then
                ret := pg_catalog.concat(ret, 'INOUT');
            else
                ret := pg_catalog.concat(ret, 'OUT');
            end if;

            ret := pg_catalog.concat(ret, ' ');
            ret := pg_catalog.concat(ret, proargnames[argIndex]);

            ret := pg_catalog.concat(ret, ' ');
            ret := pg_catalog.concat(ret, proallargtypes[argIndex]::regType::pg_catalog.text);

            argIndex := argIndex + 1;

            EXIT WHEN argIndex > allArgNum;
        END LOOP;
    else
        argTypes := string_to_array(proargtypes::text, ' ');
        allArgNum := array_length(argTypes, 1);
        if (0 < allArgNum) then
            argIndex := 1;
            LOOP
                if (1 < argIndex) then
                    ret := pg_catalog.concat(ret, ',');
                end if;

                ret := pg_catalog.concat(ret, ' IN');

                ret := pg_catalog.concat(ret, ' ');
                ret := pg_catalog.concat(ret, proargnames[argIndex]);

                ret := pg_catalog.concat(ret, ' ');
                ret := pg_catalog.concat(ret, argTypes[argIndex]::regType::pg_catalog.text);

                argIndex := argIndex + 1;
                EXIT WHEN argIndex > allArgNum;
            END LOOP;
        end if;
    end if;
    ret := pg_catalog.concat(ret, ')\n');

    ret := pg_catalog.concat(ret, prosrc);

    RETURN ret;
END
$$
IMMUTABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.get_func_def(funcName pg_catalog.text,
                                              procOwner pg_catalog.text,
                                              prorettype pg_catalog.oid,
                                              proargtypes pg_catalog.oidvector,
                                              proargnames pg_catalog.text[],
                                              prosrc pg_catalog.text,
                                              procOid pg_catalog.oid)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    argTypes pg_catalog.int4[];
    allArgNum pg_catalog.int4;
    argIndex pg_catalog.int4;
    definerVal pg_catalog.text;
    definerUser pg_catalog.text;
    definerHost pg_catalog.text;
    atPos pg_catalog.int4;
BEGIN
    definerVal := coalesce(mysql.get_plmysql_config($7, 'plmysql.definer'),
                           pg_catalog.concat($2, '@%'));
    atPos := pg_catalog.strpos(definerVal, '@');
    if (atPos > 0) then
        definerUser := pg_catalog.substr(definerVal, 1, atPos - 1);
        definerHost := pg_catalog.substr(definerVal, atPos + 1);
    else
        definerUser := definerVal;
        definerHost := '%';
    end if;

    ret := 'CREATE DEFINER=`';
    ret := pg_catalog.concat(ret, definerUser);
    ret := pg_catalog.concat(ret, '`@`');
    ret := pg_catalog.concat(ret, definerHost);
    ret := pg_catalog.concat(ret, '` FUNCTION `');
    ret := pg_catalog.concat(ret, funcName);
    ret := pg_catalog.concat(ret, '`(');
    argTypes := string_to_array(proargtypes::text, ' ');
    allArgNum := array_length(argTypes, 1);
    argIndex := 1;
    if (0 < allArgNum) then
        LOOP
            if (1 < argIndex) then
                ret := pg_catalog.concat(ret, ', ');
            end if;

            ret := pg_catalog.concat(ret, proargnames[argIndex]);
            ret := pg_catalog.concat(ret, ' ');
            ret := pg_catalog.concat(ret, argTypes[argIndex]::regType::text);

            argIndex := argIndex + 1;
            EXIT WHEN argIndex > allArgNum;
        END LOOP;
    end if;
    ret := pg_catalog.concat(ret, ')');

    -- ret := pg_catalog.concat(ret, "\n");
    ret := pg_catalog.concat(ret, ' ');
    ret := pg_catalog.concat(ret, 'RETURNS ', prorettype::regType::text);

    ret := pg_catalog.concat(ret, '\n');
    ret := pg_catalog.concat(ret, prosrc);

    RETURN ret;
END
$$
IMMUTABLE LANGUAGE PLPGSQL;

/*
 * Definer row of mys_informa_schema shows the account recorded at CREATE
 * time (user@host), falling back to the owner with MySQL's default host
 * pattern for routines created without DEFINER or outside the MySQL
 * protocol path.  Created/Modified likewise prefer the proconfig timestamps.
 */
CREATE VIEW mys_informa_schema.functions AS
SELECT
    (select ns.nspname from pg_namespace ns where ns.oid = pc.pronamespace)::varchar(256) as Db,
    pc.proname::varchar(256) as Name,
    'FUNCTION'::varchar(256) as Type,
    (mysql.get_func_def(pc.proname, (select au.rolname from pg_authid au where au.oid = pc.proowner), pc.prorettype, pc.proargtypes, pc.proargnames, pc.prosrc, pc.oid))::text as Define,
    coalesce(mysql.get_plmysql_config(pc.oid, 'plmysql.definer'),
             (select au.rolname from pg_authid au where au.oid = pc.proowner))::varchar(256) as Definer,
    mysql.get_plmysql_config(pc.oid, 'plmysql.last_altered')::varchar(256) as Modified,
    mysql.get_plmysql_config(pc.oid, 'plmysql.created')::varchar(256) as Created,
    'DEFINER'::varchar(256) as Security_type,
    ''::varchar(512) as Comment,
    'utf8mb4'::varchar(128) as Character_set_client,
    'utf8mb4_general_ci'::varchar(128) as Collation_connection,
    'utf8mb4_general_ci'::varchar(128) as Database_Collation
FROM pg_proc pc
WHERE pc.prokind = 'f' and substring(pc.proname from 1 for 21) != 'func_reset_serial_for';

CREATE VIEW mys_informa_schema.procedures AS
SELECT
    (select ns.nspname from pg_namespace ns where ns.oid = pc.pronamespace)::varchar(256) as Db,
    pc.proname::varchar(256) as Name,
    'PROCEDURE'::varchar(256) as Type,
    (mysql.get_proc_def(pc.proname, (select au.rolname from pg_authid au where au.oid = pc.proowner), pc.proargtypes, pc.proallargtypes, pc.proargmodes, pc.proargnames, pc.prosrc, pc.oid))::text as Define,
    coalesce(mysql.get_plmysql_config(pc.oid, 'plmysql.definer'),
             (select au.rolname from pg_authid au where au.oid = pc.proowner))::varchar(256) as Definer,
    mysql.get_plmysql_config(pc.oid, 'plmysql.last_altered')::varchar(256) as Modified,
    mysql.get_plmysql_config(pc.oid, 'plmysql.created')::varchar(256) as Created,
    'DEFINER'::varchar(256) as Security_type,
    ''::varchar(512) as Comment,
    'utf8mb4'::varchar(128) as Character_set_client,
    'utf8mb4_general_ci'::varchar(128) as Collation_connection,
    'utf8mb4_general_ci'::varchar(128) as Database_Collation
FROM pg_proc pc
WHERE pc.prokind = 'p' and substring(pc.proname from 1 for 21) != 'func_reset_serial_for';

/*
 * SHOW CREATE's sql_mode column is the CREATE-time snapshot, not the
 * caller's current session mode; the routines/functions views now expose it.
 */
CREATE OR REPLACE VIEW mys_informa_schema.routines AS
    SELECT
        proname::varchar(64) AS specific_name,
        'def'::varchar(512) AS routine_catalog,
        pronamespace::regnamespace::varchar(64) AS routine_schema,
        proname::varchar(64) AS routine_name,
        (CASE WHEN pg_proc.prokind = 'f'::text THEN 'FUNCTION' ELSE 'PROCEDURE' END)::varchar(9) AS routine_type,
        (CASE
            WHEN pg_proc.prokind = 'f'::text THEN
                (SELECT CASE
                    WHEN ty.typname = 'tinyint' THEN 'tinyint'
                    WHEN ty.typname = 'tinyint signed' THEN 'tinyint signed'
                    WHEN ty.typname = 'tinyint unsigned' THEN 'tinyint unsigned'
                    WHEN ty.typname = 'smallint' THEN 'smallint'
                    WHEN ty.typname = 'smallint signed' THEN 'smallint signed'
                    WHEN ty.typname = 'smallint unsigned' THEN 'smallint unsigned'
                    WHEN ty.typname = 'mediumint' THEN 'mediumint'
                    WHEN ty.typname = 'mediumint signed' THEN 'mediumint signed'
                    WHEN ty.typname = 'mediumint unsigned' THEN 'mediumint unsigned'
                    WHEN ty.typname = 'int4' THEN 'int'
                    WHEN ty.typname = 'int signed' THEN 'int signed'
                    WHEN ty.typname = 'int unsigned' THEN 'int unsigned'
                    WHEN ty.typname = 'int8' THEN 'bigint'
                    WHEN ty.typname = 'bigint signed' THEN 'bigint signed'
                    WHEN ty.typname = 'bigint unsigned' THEN 'bigint unsigned'
                    WHEN ty.typname = 'varchar' THEN 'varchar'
                    WHEN ty.typname = 'bpchar' THEN 'char'
                    WHEN ty.typname = 'text' THEN 'text'
                    WHEN ty.typname = 'date' THEN 'date'
                    WHEN ty.typname = 'time' THEN 'time'
                    WHEN ty.typname = 'datetime' THEN 'datetime'
                    WHEN ty.typname = 'timestamp' THEN 'timestamp'
                    WHEN ty.typname = 'bit' THEN 'bit'
                    WHEN ty.typname = 'varbit' THEN 'bit'
                    WHEN ty.typname = 'binary' THEN 'binary'
                    WHEN ty.typname = 'varbinary' THEN 'varbinary'
                    WHEN ty.typname = 'tinyblob' THEN 'tinyblob'
                    WHEN ty.typname = 'blob' THEN 'blob'
                    WHEN ty.typname = 'mediumblob' THEN 'mediumblob'
                    WHEN ty.typname = 'longblob' THEN 'longblob'
                    WHEN mysql.left(ty.typname, 5) = 'float' THEN 'float'
                    WHEN ty.typname = 'double' THEN 'double'
                    WHEN ty.typname = 'decimal' THEN 'decimal'
                    WHEN ty.typname = 'numeric' THEN 'decimal'
                    WHEN ty.typname = 'real' THEN 'double'
                    WHEN ty.typname = 'year_' THEN 'year'
                    ELSE ty.typname
                END FROM pg_catalog.pg_type ty WHERE ty.oid = prorettype)
            ELSE ''
        END)::varchar(64) AS data_type,
        NULL::int AS character_maximum_length,
        NULL::int AS character_octet_length,
        NULL::bigint AS numeric_precision,
        NULL::int AS numeric_scale,
        NULL::bigint AS datetime_precision,
        NULL::varchar(64) AS character_set_name,
        NULL::varchar(64) AS collation_name,
        (CASE
            WHEN pg_proc.prokind = 'f'::text THEN
                (SELECT CASE
                    WHEN ty.typname = 'tinyint' THEN 'tinyint'
                    WHEN ty.typname = 'tinyint signed' THEN 'tinyint signed'
                    WHEN ty.typname = 'tinyint unsigned' THEN 'tinyint unsigned'
                    WHEN ty.typname = 'smallint' THEN 'smallint'
                    WHEN ty.typname = 'smallint signed' THEN 'smallint signed'
                    WHEN ty.typname = 'smallint unsigned' THEN 'smallint unsigned'
                    WHEN ty.typname = 'mediumint' THEN 'mediumint'
                    WHEN ty.typname = 'mediumint signed' THEN 'mediumint signed'
                    WHEN ty.typname = 'mediumint unsigned' THEN 'mediumint unsigned'
                    WHEN ty.typname = 'int4' THEN 'int'
                    WHEN ty.typname = 'int signed' THEN 'int signed'
                    WHEN ty.typname = 'int unsigned' THEN 'int unsigned'
                    WHEN ty.typname = 'int8' THEN 'bigint'
                    WHEN ty.typname = 'bigint signed' THEN 'bigint signed'
                    WHEN ty.typname = 'bigint unsigned' THEN 'bigint unsigned'
                    WHEN ty.typname = 'varchar' THEN 'varchar'
                    WHEN ty.typname = 'bpchar' THEN 'char'
                    WHEN ty.typname = 'text' THEN 'text'
                    WHEN ty.typname = 'date' THEN 'date'
                    WHEN ty.typname = 'time' THEN 'time'
                    WHEN ty.typname = 'datetime' THEN 'datetime'
                    WHEN ty.typname = 'timestamp' THEN 'timestamp'
                    WHEN ty.typname = 'bit' THEN 'bit'
                    WHEN ty.typname = 'varbit' THEN 'bit'
                    WHEN ty.typname = 'binary' THEN 'binary'
                    WHEN ty.typname = 'varbinary' THEN 'varbinary'
                    WHEN ty.typname = 'tinyblob' THEN 'tinyblob'
                    WHEN ty.typname = 'blob' THEN 'blob'
                    WHEN ty.typname = 'mediumblob' THEN 'mediumblob'
                    WHEN ty.typname = 'longblob' THEN 'longblob'
                    WHEN mysql.left(ty.typname, 5) = 'float' THEN 'float'
                    WHEN ty.typname = 'double' THEN 'double'
                    WHEN ty.typname = 'decimal' THEN 'decimal'
                    WHEN ty.typname = 'numeric' THEN 'decimal'
                    WHEN ty.typname = 'real' THEN 'double'
                    WHEN ty.typname = 'year_' THEN 'year'
                    ELSE ty.typname
                END FROM pg_catalog.pg_type ty WHERE ty.oid = prorettype)
            ELSE ''
        END)::text AS dtd_identifier,
        'SQL'::varchar(8) AS routine_body,
        prosrc::text AS routine_definition,
        NULL::varchar(64) AS external_name,
        NULL::varchar(64) AS external_language,
        'SQL'::varchar(8) AS parameter_style,
        (CASE WHEN provolatile = 'i' THEN 'YES' ELSE 'NO' END)::varchar(3) AS is_deterministic,
        'MODIFIES SQL DATA'::varchar(64) AS sql_data_access,
        NULL::varchar(64) AS sql_path,
        'DEFINER'::varchar(7) AS security_type,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.created'),
                 '2024-1-1')::mysql.datetime AS created,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.last_altered'),
                 '2024-1-1')::mysql.datetime AS last_altered,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.sql_mode'),
                 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION')::varchar(8192) AS sql_mode,
        coalesce(pg_catalog.obj_description(oid, 'pg_proc'), '')::text AS routine_comment,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.definer'),
                 pg_catalog.concat(pg_get_userbyid(proowner), '@%'))::varchar(93) AS definer,
        'utf8mb4'::varchar(32) AS character_set_client,
        'utf8mb4_general_ci'::varchar(32) AS collation_connection,
        'utf8_general_ci'::varchar(32) AS database_collation
    FROM pg_proc
    WHERE pronamespace NOT IN ('pg_catalog'::regnamespace, 'mysql'::regnamespace)
      AND substring(proname FROM 1 FOR 21) != 'func_reset_serial_for'
      AND prorettype != 2279;

CREATE OR REPLACE VIEW mysql.proc AS
    SELECT
        pronamespace::regnamespace::char(64) AS db,
        proname::char(64) AS name,
        (CASE WHEN pg_proc.prokind = 'f'::text THEN 'FUNCTION' ELSE 'PROCEDURE' END)::varchar(9) AS type,
        proname::char(64) AS specific_name,
        'SQL'::varchar(8) AS language,
        'MODIFIES_SQL_DATA'::varchar(64) AS sql_data_access,
        (CASE WHEN provolatile = 'i' THEN 'YES' ELSE 'NO' END)::varchar(3) AS is_deterministic,
        'DEFINER'::varchar(7) AS security_type,
        pg_get_function_arguments(oid)::mysql.blob AS param_list,
        pg_get_function_result(oid)::mysql.blob AS returns,
        prosrc::mysql.blob AS body,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.definer'),
                 pg_catalog.concat(pg_get_userbyid(proowner), '@%'))::char(93) AS definer,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.created'),
                 '2024-1-1')::timestamptz AS created,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.last_altered'),
                 '2024-1-1')::timestamptz AS modified,
        coalesce(mysql.get_plmysql_config(oid, 'plmysql.sql_mode'),
                 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION')::varchar(8192) AS sql_mode,
        coalesce(pg_catalog.obj_description(oid, 'pg_proc'), '')::text AS comment,
        'utf8mb4'::char(32) AS character_set_client,
        'utf8mb4_general_ci'::char(32) AS collation_connection,
        'utf8_general_ci'::char(32) AS db_collation,
        prosrc::mysql.blob AS body_utf8
    FROM pg_proc
    WHERE pronamespace NOT IN ('pg_catalog'::regnamespace, 'mysql'::regnamespace)
      AND substring(proname FROM 1 FOR 21) != 'func_reset_serial_for'
      AND prorettype != 2279;

/*
 * SHOW CREATE now reports the routine's CREATE-time sql_mode snapshot (the
 * caller's current session mode is irrelevant by then) and the recorded
 * DEFINER account via the formatters.
 */
CREATE OR REPLACE FUNCTION mysql.show_create_function(pg_catalog.text, pg_catalog.text)
RETURNS setof RECORD
AS
$$
DECLARE
    schName pg_catalog.varchar(128);
    funcName pg_catalog.varchar(128);
    func RECORD;
    recordNum pg_catalog.int4;
BEGIN
    schName := $1;
    funcName := $2;
    recordNum := 0;

    FOR func IN
        select
            Name,
            (select mysql.get_plmysql_config(p.oid, 'plmysql.sql_mode')
             from pg_catalog.pg_proc p
             join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = schName and p.proname = funcName
               and p.prokind = 'f')::varchar(256) as sql_mode,
            Define,
            Character_set_client,
            Collation_connection,
            Database_Collation
        FROM mys_informa_schema.functions
        WHERE Db = schName and Name = funcName
    LOOP
        recordNum := recordNum + 1;
        return next func;
    END LOOP;

    if (recordNum = 0) then
        raise exception 'FUNCTION % does not exist', funcName;
    end if;

    return;
END;
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.show_create_procedure(pg_catalog.text, pg_catalog.text)
RETURNS setof RECORD
AS
$$
DECLARE
    schName pg_catalog.varchar(128);
    procName pg_catalog.varchar(128);
    proc RECORD;
    recordNum pg_catalog.int4;
BEGIN
    schName := $1;
    procName := $2;
    recordNum := 0;

    FOR proc IN
        select
            Name,
            (select mysql.get_plmysql_config(p.oid, 'plmysql.sql_mode')
             from pg_catalog.pg_proc p
             join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = schName and p.proname = procName
               and p.prokind = 'p')::varchar(256) as sql_mode,
            Define,
            Character_set_client,
            Collation_connection,
            Database_Collation
        FROM mys_informa_schema.procedures
        WHERE Db = schName and Name = procName
    LOOP
        recordNum := recordNum + 1;
        return next proc;
    END LOOP;

    if (recordNum = 0) then
        raise exception 'PROCEDURE % does not exist', procName;
    end if;

    return;
END;
$$
IMMUTABLE LANGUAGE plpgsql;

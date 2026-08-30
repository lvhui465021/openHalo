/*
 * aux_mysql 1.9 -> 1.10
 *
 * MySQL stores a routine's SQL-data-access characteristic even though it is
 * advisory.  plmysql records explicit characteristics in pg_proc.proconfig
 * as plmysql.sql_data_access; routines created by earlier versions get the
 * MySQL 5.7 default, CONTAINS SQL.
 */

CREATE OR REPLACE FUNCTION mysql.get_plmysql_sql_data_access(routineOid pg_catalog.oid)
RETURNS pg_catalog.text
AS
$$
    SELECT coalesce(mysql.get_plmysql_config(routineOid,
                                               'plmysql.sql_data_access'),
                    'CONTAINS SQL')
$$
STABLE LANGUAGE sql;

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
    dataAccessVal pg_catalog.text;
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
    dataAccessVal := mysql.get_plmysql_sql_data_access($8);

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
    ret := pg_catalog.concat(ret, ') ', dataAccessVal, '\n');
    ret := pg_catalog.concat(ret, prosrc);
    RETURN ret;
END
$$
STABLE LANGUAGE PLPGSQL;

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
    dataAccessVal pg_catalog.text;
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
    dataAccessVal := mysql.get_plmysql_sql_data_access($7);

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
    ret := pg_catalog.concat(ret, ') RETURNS ', prorettype::regType::text,
                             ' ', dataAccessVal, '\n');
    ret := pg_catalog.concat(ret, prosrc);
    RETURN ret;
END
$$
STABLE LANGUAGE PLPGSQL;

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
        mysql.get_plmysql_sql_data_access(oid)::varchar(64) AS sql_data_access,
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
        pg_catalog.replace(mysql.get_plmysql_sql_data_access(oid), ' ', '_')::varchar(64) AS sql_data_access,
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

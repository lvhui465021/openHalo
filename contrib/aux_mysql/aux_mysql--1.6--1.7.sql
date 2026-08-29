/*
 * aux_mysql 1.6 -> 1.7
 *
 * CREATE ... COMMENT has been stored in pg_description since 1.6, but the
 * MySQL compatibility views still returned an empty literal.  Surface the
 * persisted value through the two MySQL 5.7 routine metadata interfaces.
 * ROUTINE_BODY and mysql.proc.language deliberately remain SQL: those are
 * the values specified by MySQL for stored routines, independent of the
 * implementation language used internally by openHalo.
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
        '2024-1-1'::mysql.datetime AS created,
        '2024-1-1'::mysql.datetime AS last_altered,
        'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'::varchar(8192) AS sql_mode,
        coalesce(pg_catalog.obj_description(oid, 'pg_proc'), '')::text AS routine_comment,
        pg_catalog.concat(pg_get_userbyid(proowner), '@%')::varchar(93) AS definer,
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
        pg_catalog.concat(pg_get_userbyid(proowner), '@%')::char(93) AS definer,
        '2024-1-1'::timestamptz AS created,
        '2024-1-1'::timestamptz AS modified,
        'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'::varchar(8192) AS sql_mode,
        coalesce(pg_catalog.obj_description(oid, 'pg_proc'), '')::text AS comment,
        'utf8mb4'::char(32) AS character_set_client,
        'utf8mb4_general_ci'::char(32) AS collation_connection,
        'utf8_general_ci'::char(32) AS db_collation,
        prosrc::mysql.blob AS body_utf8
    FROM pg_proc
    WHERE pronamespace NOT IN ('pg_catalog'::regnamespace, 'mysql'::regnamespace)
      AND substring(proname FROM 1 FOR 21) != 'func_reset_serial_for'
      AND prorettype != 2279;

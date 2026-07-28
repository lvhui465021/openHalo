-- \echo mysql_adapter extension loading 1.1

-- -----------------------------------------------------------------------------
-- Schemas
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS mysql;
GRANT USAGE ON SCHEMA mysql TO PUBLIC;

-- -----------------------------------------------------------------------------
-- MySQL-compatible type domains
-- -----------------------------------------------------------------------------

CREATE DOMAIN mysql.tinyint AS pg_catalog.int2 CHECK ((-128 <= VALUE) AND (VALUE <= 127));
CREATE DOMAIN mysql."tinyint signed" AS pg_catalog.int2 CHECK ((-128 <= VALUE) AND (VALUE <= 127));
CREATE DOMAIN mysql."tinyint unsigned" AS pg_catalog.int2 CHECK ((0 <= VALUE) AND (VALUE <= 255));
CREATE DOMAIN mysql.tinyint1 AS pg_catalog.int2 CHECK ((-128 <= VALUE) AND (VALUE <= 127));
CREATE DOMAIN mysql."tinyint1 signed" AS pg_catalog.int2 CHECK ((-128 <= VALUE) AND (VALUE <= 127));
CREATE DOMAIN mysql."tinyint1 unsigned" AS pg_catalog.int2 CHECK ((0 <= VALUE) AND (VALUE <= 255));

CREATE DOMAIN mysql.smallint AS pg_catalog.int2;
CREATE DOMAIN mysql."smallint signed" AS pg_catalog.int2;
CREATE DOMAIN mysql."smallint unsigned" AS pg_catalog.int4 CHECK ((0 <= VALUE) AND (VALUE <= 65535));

CREATE DOMAIN mysql.mediumint AS pg_catalog.int4 CHECK ((-8388608 <= VALUE) AND (VALUE <= 8388607));
CREATE DOMAIN mysql."mediumint signed" AS pg_catalog.int4 CHECK ((-8388608 <= VALUE) AND (VALUE <= 8388607));
CREATE DOMAIN mysql."mediumint unsigned" AS pg_catalog.int4 CHECK ((0 <= VALUE) AND (VALUE <= 16777215));

CREATE DOMAIN mysql."int signed" AS pg_catalog.int4;
CREATE DOMAIN mysql."int unsigned" AS pg_catalog.int8 CHECK ((0 <= VALUE) AND (VALUE <= 4294967295));

CREATE DOMAIN mysql.int AS pg_catalog.int4;
CREATE DOMAIN mysql.integer AS pg_catalog.int4;

CREATE DOMAIN mysql."bigint signed" AS pg_catalog.int8;
CREATE DOMAIN mysql."bigint unsigned" AS pg_catalog.int8 CHECK ((0 <= VALUE) AND (VALUE <= 9223372036854775807));

CREATE DOMAIN mysql.real AS pg_catalog.float8;
CREATE DOMAIN mysql.double AS pg_catalog.float8;

CREATE DOMAIN mysql.datetime AS pg_catalog.timestamp;

CREATE DOMAIN mysql.binary AS pg_catalog.bytea;
CREATE DOMAIN mysql.varbinary AS pg_catalog.bytea;
CREATE DOMAIN mysql.blob AS pg_catalog.bytea;

CREATE DOMAIN mysql.year_ AS pg_catalog.int4 CHECK ((1901 <= VALUE) AND (VALUE <= 2155));

-- -----------------------------------------------------------------------------
-- Cast overrides: pg_catalog type casts for MySQL compatibility
--
-- NOTE: These UPDATE pg_cast statements change castcontext globally,
-- affecting ALL databases, not just the current one.  This is necessary
-- for MySQL WHERE-clause semantics (e.g. "WHERE int_col" treating
-- non-zero as true).  The downgrade script (1.1->1.0) restores the
-- original explicit-only castcontext.
-- -----------------------------------------------------------------------------

-- int -> boolean (MySQL: non-zero is true, zero is false)
UPDATE pg_cast SET castcontext = 'i' WHERE castsource = 23 AND casttarget = 16;
UPDATE pg_cast SET castcontext = 'a' WHERE castsource = 16 AND casttarget = 23;

-- -----------------------------------------------------------------------------
-- Boolean-to-integer casts (MySQL compatibility)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION mysql.cast_boolean_to_tinyint(pg_catalog.bool)
RETURNS int2
AS $$
BEGIN
    IF $1 THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
END;
$$ LANGUAGE plpgsql STRICT;
CREATE CAST (pg_catalog.bool AS int2) WITH FUNCTION mysql.cast_boolean_to_tinyint AS ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.cast_boolean_to_bigint(pg_catalog.bool)
RETURNS int8
AS $$
BEGIN
    IF $1 THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
END;
$$ LANGUAGE plpgsql STRICT;
CREATE CAST (pg_catalog.bool AS int8) WITH FUNCTION mysql.cast_boolean_to_bigint AS ASSIGNMENT;

-- -----------------------------------------------------------------------------
-- MySQL-compatible scalar functions: v1.0 builtins
-- -----------------------------------------------------------------------------

-- repeat(text, int) -- wraps pg_catalog.repeat in the mysql schema.
-- MySQL REPEAT('ab', 3) => 'ababab'
CREATE OR REPLACE FUNCTION mysql.repeat(text, int)
RETURNS text
AS 'SELECT pg_catalog.repeat($1, $2)'
LANGUAGE SQL IMMUTABLE STRICT;

-- unhex(text) -- MySQL UNHEX('616263') => x'616263'::bytea
CREATE OR REPLACE FUNCTION mysql.unhex(text)
RETURNS bytea
AS $$SELECT pg_catalog.decode($1, 'hex')$$
LANGUAGE SQL IMMUTABLE STRICT;

-- to_base64(bytea) -- MySQL TO_BASE64(x'616263') => 'YWJj'
CREATE OR REPLACE FUNCTION mysql.to_base64(bytea)
RETURNS text
AS $$SELECT pg_catalog.encode($1, 'base64')$$
LANGUAGE SQL IMMUTABLE STRICT;

-- from_base64(text) -- MySQL FROM_BASE64('YWJj') => x'616263'::bytea
CREATE OR REPLACE FUNCTION mysql.from_base64(text)
RETURNS bytea
AS $$SELECT pg_catalog.decode($1, 'base64')$$
LANGUAGE SQL IMMUTABLE STRICT;

-- =============================================================================
-- M3: MySQL-compatible information_schema (mys_informa_schema)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- mys_informa_schema: MySQL clients query this schema for metadata.
-- The MySQL wire-protocol layer rewrites "information_schema.X" to
-- "mys_informa_schema.X" at parse time.
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS mys_informa_schema;
GRANT USAGE ON SCHEMA mys_informa_schema TO PUBLIC;

-- -----------------------------------------------------------------------------
-- Helper: mysql.amend_def_val -- strip type casts and nextval from defaults
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION mysql.amend_def_val(pg_catalog.text)
RETURNS pg_catalog.text
AS $$
DECLARE
    ret pg_catalog.text;
    tmp pg_catalog.int4;
BEGIN
    tmp := position('nextval' in $1);
    IF 1 = tmp THEN
        ret := NULL;
    ELSE
        tmp := position('::' in $1);
        IF 0 < tmp THEN
            ret := substring($1 from 1 for (tmp - 1));
            IF lower(ret) = 'null' THEN
                ret := NULL;
            END IF;
        ELSE
            ret := $1;
        END IF;
    END IF;
    RETURN ret;
END
$$ LANGUAGE plpgsql STRICT;

-- -----------------------------------------------------------------------------
-- Helper: mysql.get_seq_in_index -- sequence position of a column in an index
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION mysql.get_seq_in_index(pg_catalog.text, pg_catalog.int2vector)
RETURNS pg_catalog.int2
AS $$
DECLARE
    items pg_catalog.text[];
    itemsNum int;
BEGIN
    items := string_to_array($2::text, ' ');
    itemsNum := array_length(items, 1);
    FOR i IN 1..itemsNum LOOP
        IF ($1 = items[i]) THEN
            RETURN i;
        END IF;
    END LOOP;
    RETURN 0;
END
$$ LANGUAGE plpgsql STRICT;

-- -----------------------------------------------------------------------------
-- View: mys_informa_schema.schemata
-- Maps to MySQL: SHOW DATABASES / SELECT * FROM information_schema.schemata
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW mys_informa_schema.schemata AS
SELECT
    'def'::varchar(256)                            AS CATALOG_NAME,
    d.datname::varchar(256)                        AS SCHEMA_NAME,
    'utf8mb4'::varchar(256)                        AS DEFAULT_CHARACTER_SET_NAME,
    'utf8mb4_general_ci'::varchar(256)             AS DEFAULT_COLLATION_NAME,
    NULL::varchar(256)                             AS SQL_PATH
FROM pg_catalog.pg_database d
ORDER BY 1, 2;

-- -----------------------------------------------------------------------------
-- View: mys_informa_schema.tables
-- Maps to MySQL: SHOW TABLES / SELECT * FROM information_schema.tables
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW mys_informa_schema.tables AS
SELECT
    'def'::varchar(256)                            AS TABLE_CATALOG,
    ns.nspname::varchar(256)                       AS TABLE_SCHEMA,
    cl.relname::varchar(256)                       AS TABLE_NAME,
    CASE cl.relkind
        WHEN 'r' THEN 'BASE TABLE'
        WHEN 'p' THEN 'BASE TABLE'
        WHEN 'v' THEN 'VIEW'
        ELSE 'BASE TABLE'
    END::varchar(256)                              AS TABLE_TYPE,
    'InnoDB'::varchar(256)                         AS ENGINE,
    10::bigint                                     AS VERSION,
    'Dynamic'::varchar(256)                        AS ROW_FORMAT,
    cl.reltuples::bigint                           AS TABLE_ROWS,
    100::bigint                                    AS AVG_ROW_LENGTH,
    16384::bigint                                  AS DATA_LENGTH,
    16384::bigint                                  AS MAX_DATA_LENGTH,
    16384::bigint                                  AS INDEX_LENGTH,
    16384::bigint                                  AS DATA_FREE,
    NULL::bigint                                   AS AUTO_INCREMENT,
    NULL::timestamp                                AS CREATE_TIME,
    NULL::timestamp                                AS UPDATE_TIME,
    NULL::timestamp                                AS CHECK_TIME,
    'utf8mb4_general_ci'::varchar(256)             AS TABLE_COLLATION,
    NULL::bigint                                   AS CHECKSUM,
    ''::varchar(256)                               AS CREATE_OPTIONS,
    pg_catalog.obj_description(cl.oid)::varchar(512) AS TABLE_COMMENT
FROM pg_catalog.pg_class cl
JOIN pg_catalog.pg_namespace ns ON ns.oid = cl.relnamespace
WHERE cl.relkind IN ('r', 'p', 'v')
  AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
  AND ns.nspname !~ '^pg_'
ORDER BY 1, 2, 3;

-- -----------------------------------------------------------------------------
-- View: mys_informa_schema.columns
-- Maps to MySQL: SHOW COLUMNS FROM / DESCRIBE / SELECT * FROM
--                information_schema.columns
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW mys_informa_schema.columns AS
SELECT
    'def'::varchar(256)                            AS TABLE_CATALOG,
    ns.nspname::varchar(256)                       AS TABLE_SCHEMA,
    cl.relname::varchar(256)                       AS TABLE_NAME,
    att.attname::varchar(256)                      AS COLUMN_NAME,
    att.attnum::bigint                             AS ORDINAL_POSITION,
    mysql.amend_def_val(
        pg_catalog.pg_get_expr(ad.adbin, ad.adrelid)
    )::text                                        AS COLUMN_DEFAULT,
    CASE WHEN att.attnotnull THEN 'NO' ELSE 'YES'
    END::varchar(8)                                AS IS_NULLABLE,
    -- Map pg_catalog type names to MySQL type names
    CASE ty.typname
        WHEN 'int2'    THEN 'smallint'
        WHEN 'int4'    THEN 'int'
        WHEN 'int8'    THEN 'bigint'
        WHEN 'float4'  THEN 'float'
        WHEN 'float8'  THEN 'double'
        WHEN 'bool'    THEN 'tinyint'
        WHEN 'varchar' THEN 'varchar'
        WHEN 'bpchar'  THEN 'char'
        WHEN 'text'    THEN 'text'
        WHEN 'bytea'   THEN 'blob'
        WHEN 'time'    THEN 'time'
        WHEN 'date'    THEN 'date'
        WHEN 'timetz'  THEN 'time'
        WHEN 'timestamp'   THEN 'datetime'
        WHEN 'timestamptz' THEN 'datetime'
        WHEN 'numeric' THEN 'decimal'
        WHEN 'bit'     THEN 'bit'
        WHEN 'varbit'  THEN 'bit'
        ELSE ty.typname
    END::varchar(64)                               AS DATA_TYPE,
    CASE WHEN ty.typname IN ('varchar', 'bpchar')
         THEN att.atttypmod - 4
         ELSE NULL
    END::bigint                                    AS CHARACTER_MAXIMUM_LENGTH,
    NULL::bigint                                   AS CHARACTER_OCTET_LENGTH,
    NULL::bigint                                   AS NUMERIC_PRECISION,
    NULL::bigint                                   AS NUMERIC_SCALE,
    NULL::bigint                                   AS DATETIME_PRECISION,
    'utf8mb4'::varchar(256)                        AS CHARACTER_SET_NAME,
    'utf8mb4_general_ci'::varchar(256)             AS COLLATION_NAME,
    -- MySQL COLUMN_TYPE (includes length/precision)
    CASE ty.typname
        WHEN 'int2'    THEN 'smallint'
        WHEN 'int4'    THEN 'int(11)'
        WHEN 'int8'    THEN 'bigint(20)'
        WHEN 'float4'  THEN 'float'
        WHEN 'float8'  THEN 'double'
        WHEN 'bool'    THEN 'tinyint(1)'
        WHEN 'varchar' THEN pg_catalog.concat('varchar(', att.atttypmod - 4, ')')
        WHEN 'bpchar'  THEN pg_catalog.concat('char(', att.atttypmod - 4, ')')
        WHEN 'text'    THEN 'text'
        WHEN 'bytea'   THEN 'blob'
        WHEN 'time'    THEN 'time'
        WHEN 'date'    THEN 'date'
        WHEN 'timetz'  THEN 'time'
        WHEN 'timestamp'   THEN 'datetime'
        WHEN 'timestamptz' THEN 'datetime'
        WHEN 'numeric' THEN 'decimal'
        WHEN 'bit'     THEN pg_catalog.concat('bit(', att.atttypmod, ')')
        WHEN 'varbit'  THEN pg_catalog.concat('bit(',
                             CASE WHEN att.atttypmod = -1 THEN 1
                                  ELSE att.atttypmod END, ')')
        ELSE ty.typname
    END::varchar(256)                              AS COLUMN_TYPE,
    ''::text                                       AS EXTRA
FROM pg_catalog.pg_attribute att
JOIN pg_catalog.pg_class     cl  ON cl.oid = att.attrelid
JOIN pg_catalog.pg_namespace ns  ON ns.oid = cl.relnamespace
JOIN pg_catalog.pg_type      ty  ON ty.oid = att.atttypid
LEFT JOIN pg_catalog.pg_attrdef ad
    ON ad.adrelid = att.attrelid AND ad.adnum = att.attnum
WHERE att.attnum > 0
  AND NOT att.attisdropped
  AND cl.relkind IN ('r', 'p', 'v')
  AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
  AND ns.nspname !~ '^pg_'
ORDER BY 1, 2, 3, 5;

-- -----------------------------------------------------------------------------
-- View: mys_informa_schema.statistics
-- Maps to MySQL: SHOW INDEX / SELECT * FROM information_schema.statistics
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW mys_informa_schema.statistics AS
SELECT
    'def'::varchar(256)                            AS TABLE_CATALOG,
    ns.nspname::varchar(256)                       AS TABLE_SCHEMA,
    cl.relname::varchar(256)                       AS TABLE_NAME,
    CASE WHEN ind.indisunique THEN 0 ELSE 1
    END::bigint                                    AS NON_UNIQUE,
    ns.nspname::varchar(256)                       AS INDEX_SCHEMA,
    ci.relname::varchar(256)                       AS INDEX_NAME,
    mysql.get_seq_in_index(
        att.attnum::pg_catalog.text,
        ind.indkey
    )::bigint                                      AS SEQ_IN_INDEX,
    att.attname::varchar(256)                      AS COLUMN_NAME,
    'A'::varchar(256)                              AS COLLATION,
    0::bigint                                      AS CARDINALITY,
    NULL::bigint                                   AS SUB_PART,
    NULL::varchar(256)                             AS PACKED,
    CASE WHEN att.attnotnull THEN '' ELSE 'YES'
    END::varchar(256)                              AS NULLABLE,
    am.amname::varchar(256)                        AS INDEX_TYPE,
    ''::varchar(256)                               AS COMMENT,
    ''::varchar(256)                               AS INDEX_COMMENT
FROM pg_catalog.pg_index     ind
JOIN pg_catalog.pg_class     cl  ON cl.oid = ind.indrelid
JOIN pg_catalog.pg_class     ci  ON ci.oid = ind.indexrelid
JOIN pg_catalog.pg_namespace ns  ON ns.oid = cl.relnamespace
JOIN pg_catalog.pg_am        am  ON am.oid = ci.relam
JOIN pg_catalog.pg_attribute att ON att.attrelid = cl.oid
                                 AND att.attnum = ANY(ind.indkey)
WHERE cl.relkind IN ('r', 'p')
  AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
  AND ns.nspname !~ '^pg_'
ORDER BY 1, 2, 3, 4, 7;

-- -----------------------------------------------------------------------------
-- Grants for mys_informa_schema
-- -----------------------------------------------------------------------------

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA mys_informa_schema TO PUBLIC;

-- -----------------------------------------------------------------------------
-- MySQL-compatible scalar functions: v1.1 string functions
-- -----------------------------------------------------------------------------

-- CONCAT_WS(sep, str1, str2, ...)
CREATE OR REPLACE FUNCTION mysql.concat_ws(text, VARIADIC text[])
RETURNS text
AS 'SELECT pg_catalog.concat_ws($1, VARIADIC $2)'
LANGUAGE SQL IMMUTABLE;

-- FORMAT(X, D) -- format number with D decimal places
-- MySQL FORMAT(12332.123456, 4) => '12,332.1235'
CREATE OR REPLACE FUNCTION mysql.format(numeric, int)
RETURNS text
AS $$
SELECT pg_catalog.to_char($1, repeat('9', 30) || 'FM' || CASE WHEN $2 > 0 THEN '.' || repeat('9', $2) ELSE '' END)
$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.format(float8, int)
RETURNS text
AS $$
SELECT mysql.format($1::numeric, $2)
$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.format(int8, int)
RETURNS text
AS $$
SELECT mysql.format($1::numeric, $2)
$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.format(int4, int)
RETURNS text
AS $$
SELECT mysql.format($1::numeric, $2)
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- HEX(N_or_S) -- returns hexadecimal string
CREATE OR REPLACE FUNCTION mysql.hex(int8)
RETURNS text
AS 'SELECT pg_catalog.to_hex($1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.hex(int4)
RETURNS text
AS 'SELECT pg_catalog.to_hex($1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.hex(bytea)
RETURNS text
AS 'SELECT pg_catalog.encode($1, ''hex'')'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.hex(text)
RETURNS text
AS 'SELECT pg_catalog.encode($1::bytea, ''hex'')'
LANGUAGE SQL IMMUTABLE STRICT;

-- INSTR(str, substr) -- returns position of first occurrence
CREATE OR REPLACE FUNCTION mysql.instr(text, text)
RETURNS int
AS $$
SELECT CASE WHEN $2 = '' THEN 1
            WHEN pg_catalog.strpos($1, $2) = 0 THEN 0
            ELSE pg_catalog.strpos($1, $2) END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- LCASE(str)
CREATE OR REPLACE FUNCTION mysql.lcase(text)
RETURNS text
AS 'SELECT pg_catalog.lower($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- UCASE(str)
CREATE OR REPLACE FUNCTION mysql.ucase(text)
RETURNS text
AS 'SELECT pg_catalog.upper($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- LPAD(str, len, padstr)
CREATE OR REPLACE FUNCTION mysql.lpad(text, int, text)
RETURNS text
AS 'SELECT pg_catalog.lpad($1, $2, $3)'
LANGUAGE SQL IMMUTABLE STRICT;

-- RPAD(str, len, padstr)
CREATE OR REPLACE FUNCTION mysql.rpad(text, int, text)
RETURNS text
AS 'SELECT pg_catalog.rpad($1, $2, $3)'
LANGUAGE SQL IMMUTABLE STRICT;

-- LTRIM(str)
CREATE OR REPLACE FUNCTION mysql.ltrim(text)
RETURNS text
AS 'SELECT pg_catalog.ltrim($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- RTRIM(str)
CREATE OR REPLACE FUNCTION mysql.rtrim(text)
RETURNS text
AS 'SELECT pg_catalog.rtrim($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- SPACE(n)
CREATE OR REPLACE FUNCTION mysql.space(int)
RETURNS text
AS 'SELECT pg_catalog.repeat('' '', $1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- STRCMP(expr1, expr2) -- returns 0 if same, -1 if expr1 < expr2, 1 if expr1 > expr2
CREATE OR REPLACE FUNCTION mysql.strcmp(text, text)
RETURNS int
AS $$
SELECT CASE WHEN $1 < $2 THEN -1
            WHEN $1 > $2 THEN 1
            ELSE 0 END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- SUBSTRING_INDEX(str, delim, count)
CREATE OR REPLACE FUNCTION mysql.substring_index(text, text, int)
RETURNS text
AS $$
SELECT CASE
    WHEN $3 > 0 THEN pg_catalog.array_to_string((pg_catalog.string_to_array($1, $2))[1:$3], $2)
    WHEN $3 < 0 THEN pg_catalog.array_to_string(
        (pg_catalog.string_to_array($1, $2))
        [pg_catalog.array_length(pg_catalog.string_to_array($1, $2), 1) + $3 + 1 :
         pg_catalog.array_length(pg_catalog.string_to_array($1, $2), 1)],
        $2)
    ELSE ''
END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- TRIM with custom remstr (BOTH | LEADING | TRAILING)
-- MySQL TRIM([{BOTH|LEADING|TRAILING} [remstr] FROM] str)
CREATE OR REPLACE FUNCTION mysql.trim(text)
RETURNS text
AS 'SELECT pg_catalog.btrim($1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.trim(text, text)
RETURNS text
AS 'SELECT pg_catalog.btrim($1, $2)'
LANGUAGE SQL IMMUTABLE STRICT;

-- -----------------------------------------------------------------------------
-- MySQL-compatible scalar functions: v1.1 math functions
-- -----------------------------------------------------------------------------

-- CEILING(X)
CREATE OR REPLACE FUNCTION mysql.ceiling(numeric)
RETURNS numeric
AS 'SELECT pg_catalog.ceil($1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.ceiling(float8)
RETURNS float8
AS 'SELECT pg_catalog.ceil($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- CRC32(str) -- MySQL CRC32
-- PostgreSQL has no built-in CRC32; use a plpgsql implementation
CREATE OR REPLACE FUNCTION mysql.crc32(text)
RETURNS int8
AS $$
DECLARE
    c bigint := 4294967295;  -- 0xFFFFFFFF
    i int;
    ch int;
BEGIN
    FOR i IN 1..pg_catalog.length($1) LOOP
        ch := pg_catalog.ascii(pg_catalog.substr($1, i, 1));
        c := (c # ch) & 4294967295;
        FOR j IN 0..7 LOOP
            IF (c & 1) = 1 THEN
                c := ((c >> 1) # 3988292384) & 4294967295;
            ELSE
                c := (c >> 1) & 4294967295;
            END IF;
        END LOOP;
    END LOOP;
    RETURN (c # 4294967295) & 4294967295;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- DEGREES(X)
CREATE OR REPLACE FUNCTION mysql.degrees(float8)
RETURNS float8
AS 'SELECT pg_catalog.degrees($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- FLOOR(X)
CREATE OR REPLACE FUNCTION mysql.floor(numeric)
RETURNS numeric
AS 'SELECT pg_catalog.floor($1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.floor(float8)
RETURNS float8
AS 'SELECT pg_catalog.floor($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- LN(X)
CREATE OR REPLACE FUNCTION mysql.ln(float8)
RETURNS float8
AS 'SELECT pg_catalog.ln($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- LOG2(X)
CREATE OR REPLACE FUNCTION mysql.log2(float8)
RETURNS float8
AS 'SELECT pg_catalog.log(2.0::numeric, $1::numeric)::float8'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.log2(numeric)
RETURNS numeric
AS 'SELECT pg_catalog.log(2.0, $1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- LOG10(X)
CREATE OR REPLACE FUNCTION mysql.log10(float8)
RETURNS float8
AS 'SELECT pg_catalog.log($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- MOD(N, M)
CREATE OR REPLACE FUNCTION mysql.mod(numeric, numeric)
RETURNS numeric
AS 'SELECT pg_catalog.mod($1, $2)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(float8, float8)
RETURNS float8
AS 'SELECT pg_catalog.mod($1::numeric, $2::numeric)::float8'
LANGUAGE SQL IMMUTABLE STRICT;

-- PI()
CREATE OR REPLACE FUNCTION mysql.pi()
RETURNS float8
AS 'SELECT pg_catalog.pi()'
LANGUAGE SQL IMMUTABLE;

-- POW(X, Y)
CREATE OR REPLACE FUNCTION mysql.pow(float8, float8)
RETURNS float8
AS 'SELECT pg_catalog.power($1, $2)'
LANGUAGE SQL IMMUTABLE STRICT;

-- RADIANS(X)
CREATE OR REPLACE FUNCTION mysql.radians(float8)
RETURNS float8
AS 'SELECT pg_catalog.radians($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- RAND([N])
CREATE OR REPLACE FUNCTION mysql.rand()
RETURNS float8
AS 'SELECT pg_catalog.random()'
LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.rand(int4)
RETURNS float8
AS 'SELECT (((($1::int8 * 1103515245 + 12345) % 2147483647 + 2147483647) % 2147483647)::float8 / 2147483647.0)'
LANGUAGE SQL IMMUTABLE STRICT;

-- ROUND(X[, D])
CREATE OR REPLACE FUNCTION mysql.round(numeric, int DEFAULT 0)
RETURNS numeric
AS 'SELECT pg_catalog.round($1, $2)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.round(float8, int DEFAULT 0)
RETURNS float8
AS 'SELECT pg_catalog.round($1::numeric, $2)::float8'
LANGUAGE SQL IMMUTABLE STRICT;

-- SIGN(X)
CREATE OR REPLACE FUNCTION mysql.sign(numeric)
RETURNS numeric
AS 'SELECT pg_catalog.sign($1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.sign(float8)
RETURNS float8
AS 'SELECT pg_catalog.sign($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- SQRT(X)
CREATE OR REPLACE FUNCTION mysql.sqrt(numeric)
RETURNS numeric
AS 'SELECT pg_catalog.sqrt($1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.sqrt(float8)
RETURNS float8
AS 'SELECT pg_catalog.sqrt($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- TRUNCATE(X, D)
CREATE OR REPLACE FUNCTION mysql.truncate(numeric, int)
RETURNS numeric
AS 'SELECT pg_catalog.trunc($1, $2)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.truncate(float8, int)
RETURNS float8
AS 'SELECT pg_catalog.trunc($1::numeric, $2)::float8'
LANGUAGE SQL IMMUTABLE STRICT;

-- -----------------------------------------------------------------------------
-- MySQL-compatible scalar functions: v1.1 date/time functions
-- -----------------------------------------------------------------------------

-- CURDATE()
CREATE OR REPLACE FUNCTION mysql.curdate()
RETURNS date
AS 'SELECT current_date'
LANGUAGE SQL;

-- CURTIME()
CREATE OR REPLACE FUNCTION mysql.curtime()
RETURNS time
AS 'SELECT current_time'
LANGUAGE SQL;

-- CURRENT_DATE (alias)
CREATE OR REPLACE FUNCTION mysql.current_date()
RETURNS date
AS 'SELECT current_date'
LANGUAGE SQL;

-- CURRENT_TIME (alias)
CREATE OR REPLACE FUNCTION mysql.current_time()
RETURNS time
AS 'SELECT current_time'
LANGUAGE SQL;

-- DATE_ADD(date, INTERVAL expr unit) -- simplified: takes date/timestamp + interval
CREATE OR REPLACE FUNCTION mysql.date_add(timestamp, pg_catalog.interval)
RETURNS timestamp
AS 'SELECT $1 + $2'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.date_add(date, pg_catalog.interval)
RETURNS date
AS 'SELECT ($1 + $2)::date'
LANGUAGE SQL IMMUTABLE STRICT;

-- DATE_SUB(date, INTERVAL expr unit) -- simplified: takes date/timestamp - interval
CREATE OR REPLACE FUNCTION mysql.date_sub(timestamp, pg_catalog.interval)
RETURNS timestamp
AS 'SELECT $1 - $2'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.date_sub(date, pg_catalog.interval)
RETURNS date
AS 'SELECT ($1 - $2)::date'
LANGUAGE SQL IMMUTABLE STRICT;

-- DATEDIFF(expr1, expr2) -- returns expr1 - expr2 in days
CREATE OR REPLACE FUNCTION mysql.datediff(date, date)
RETURNS int
AS 'SELECT $1 - $2'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.datediff(timestamp, timestamp)
RETURNS int
AS 'SELECT ($1::date - $2::date)'
LANGUAGE SQL IMMUTABLE STRICT;

-- DAY(date)
CREATE OR REPLACE FUNCTION mysql.day(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''day'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.day(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''day'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- DAYNAME(date)
CREATE OR REPLACE FUNCTION mysql.dayname(date)
RETURNS text
AS 'SELECT pg_catalog.btrim(pg_catalog.to_char($1, ''Day''))'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.dayname(timestamp)
RETURNS text
AS 'SELECT pg_catalog.btrim(pg_catalog.to_char($1::date, ''Day''))'
LANGUAGE SQL IMMUTABLE STRICT;

-- DAYOFMONTH(date)
CREATE OR REPLACE FUNCTION mysql.dayofmonth(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''day'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- DAYOFWEEK(date) -- MySQL: 1=Sunday, 7=Saturday; PG: 0=Sunday, 6=Saturday
CREATE OR REPLACE FUNCTION mysql.dayofweek(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''dow'', $1)::int + 1'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.dayofweek(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''dow'', $1)::int + 1'
LANGUAGE SQL IMMUTABLE STRICT;

-- DAYOFYEAR(date)
CREATE OR REPLACE FUNCTION mysql.dayofyear(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''doy'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.dayofyear(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''doy'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- HOUR(time)
CREATE OR REPLACE FUNCTION mysql.hour(time)
RETURNS int
AS 'SELECT pg_catalog.date_part(''hour'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.hour(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''hour'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- MINUTE(time)
CREATE OR REPLACE FUNCTION mysql.minute(time)
RETURNS int
AS 'SELECT pg_catalog.date_part(''minute'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.minute(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''minute'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- MONTH(date)
CREATE OR REPLACE FUNCTION mysql.month(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''month'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.month(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''month'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- MONTHNAME(date)
CREATE OR REPLACE FUNCTION mysql.monthname(date)
RETURNS text
AS 'SELECT pg_catalog.btrim(pg_catalog.to_char($1, ''Month''))'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.monthname(timestamp)
RETURNS text
AS 'SELECT pg_catalog.btrim(pg_catalog.to_char($1::date, ''Month''))'
LANGUAGE SQL IMMUTABLE STRICT;

-- NOW()
CREATE OR REPLACE FUNCTION mysql.now()
RETURNS timestamp
AS 'SELECT pg_catalog.now()'
LANGUAGE SQL;

-- CURRENT_TIMESTAMP (alias)
CREATE OR REPLACE FUNCTION mysql.current_timestamp()
RETURNS timestamp
AS 'SELECT pg_catalog.now()'
LANGUAGE SQL;

-- QUARTER(date)
CREATE OR REPLACE FUNCTION mysql.quarter(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''quarter'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.quarter(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''quarter'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- SECOND(time)
CREATE OR REPLACE FUNCTION mysql.second(time)
RETURNS int
AS 'SELECT pg_catalog.floor(pg_catalog.date_part(''second'', $1))::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.second(timestamp)
RETURNS int
AS 'SELECT pg_catalog.floor(pg_catalog.date_part(''second'', $1))::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- SYSDATE() -- returns execution time (like clock_timestamp)
CREATE OR REPLACE FUNCTION mysql.sysdate()
RETURNS timestamp
AS 'SELECT pg_catalog.clock_timestamp()'
LANGUAGE SQL;

-- TIMESTAMPDIFF(unit, datetime_expr1, datetime_expr2)
CREATE OR REPLACE FUNCTION mysql.timestampdiff(text, timestamp, timestamp)
RETURNS int8
AS $$
SELECT CASE pg_catalog.lower($1)
    WHEN 'microsecond' THEN (pg_catalog.date_part('epoch', $3 - $2) * 1000000)::int8
    WHEN 'second' THEN pg_catalog.date_part('epoch', $3 - $2)::int8
    WHEN 'minute' THEN pg_catalog.date_part('epoch', $3 - $2)::int8 / 60
    WHEN 'hour' THEN pg_catalog.date_part('epoch', $3 - $2)::int8 / 3600
    WHEN 'day' THEN ($3::date - $2::date)
    WHEN 'week' THEN (($3::date - $2::date) / 7)
    WHEN 'month' THEN ((pg_catalog.date_part('year', $3)::int - pg_catalog.date_part('year', $2)::int) * 12
                       + pg_catalog.date_part('month', $3)::int - pg_catalog.date_part('month', $2)::int)
    WHEN 'quarter' THEN ((pg_catalog.date_part('year', $3)::int - pg_catalog.date_part('year', $2)::int) * 4
                         + pg_catalog.date_part('quarter', $3)::int - pg_catalog.date_part('quarter', $2)::int)
    WHEN 'year' THEN (pg_catalog.date_part('year', $3)::int - pg_catalog.date_part('year', $2)::int)
    ELSE 0
END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- TO_DAYS(date) -- number of days since year 0 (MySQL epoch)
CREATE OR REPLACE FUNCTION mysql.to_days(date)
RETURNS int
AS 'SELECT $1 - ''0001-01-01''::date + 366'
LANGUAGE SQL IMMUTABLE STRICT;

-- WEEK(date[, mode])
CREATE OR REPLACE FUNCTION mysql.week(date, int DEFAULT 0)
RETURNS int
AS $$
SELECT CASE $2
    WHEN 0 THEN pg_catalog.date_part('week', $1)::int  -- approximation
    WHEN 1 THEN pg_catalog.date_part('week', $1)::int
    ELSE pg_catalog.date_part('week', $1)::int
END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- WEEKDAY(date) -- MySQL: 0=Monday, 6=Sunday; PG dow: 0=Sunday, 6=Saturday
CREATE OR REPLACE FUNCTION mysql.weekday(date)
RETURNS int
AS $$
SELECT CASE pg_catalog.date_part('dow', $1)::int
    WHEN 0 THEN 6  -- Sunday
    ELSE pg_catalog.date_part('dow', $1)::int - 1
END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- YEAR(date)
CREATE OR REPLACE FUNCTION mysql.year(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''year'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.year(timestamp)
RETURNS int
AS 'SELECT pg_catalog.date_part(''year'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- YEARWEEK(date)
CREATE OR REPLACE FUNCTION mysql.yearweek(date)
RETURNS int
AS 'SELECT pg_catalog.date_part(''year'', $1)::int * 100 + pg_catalog.date_part(''week'', $1)::int'
LANGUAGE SQL IMMUTABLE STRICT;

-- -----------------------------------------------------------------------------
-- MySQL-compatible scalar functions: v1.1 crypto functions
-- -----------------------------------------------------------------------------

-- MD5(str)
CREATE OR REPLACE FUNCTION mysql.md5(text)
RETURNS text
AS 'SELECT pg_catalog.md5($1)'
LANGUAGE SQL IMMUTABLE STRICT;

-- SHA1(str) -- requires pgcrypto extension for digest()
CREATE OR REPLACE FUNCTION mysql.sha1(text)
RETURNS text
AS 'SELECT pg_catalog.encode(digest($1, ''sha1''), ''hex'')'
LANGUAGE SQL IMMUTABLE STRICT;

-- SHA2(str, hash_length) -- requires pgcrypto extension for digest()
CREATE OR REPLACE FUNCTION mysql.sha2(text, int)
RETURNS text
AS $$
SELECT CASE $2
    WHEN 0 THEN pg_catalog.encode(digest($1, 'sha256'), 'hex')
    WHEN 224 THEN pg_catalog.encode(digest($1, 'sha224'), 'hex')
    WHEN 256 THEN pg_catalog.encode(digest($1, 'sha256'), 'hex')
    WHEN 384 THEN pg_catalog.encode(digest($1, 'sha384'), 'hex')
    WHEN 512 THEN pg_catalog.encode(digest($1, 'sha512'), 'hex')
    ELSE NULL
END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- -----------------------------------------------------------------------------
-- MySQL-compatible scalar functions: v1.1 information functions
-- -----------------------------------------------------------------------------

-- DATABASE()
CREATE OR REPLACE FUNCTION mysql.database()
RETURNS text
AS 'SELECT pg_catalog.current_database()'
LANGUAGE SQL;

-- USER()
CREATE OR REPLACE FUNCTION mysql.user()
RETURNS text
AS 'SELECT current_user'
LANGUAGE SQL;

-- VERSION()
CREATE OR REPLACE FUNCTION mysql.version()
RETURNS text
AS 'SELECT pg_catalog.current_setting(''mysql.server_version'')'
LANGUAGE SQL;

-- CONNECTION_ID()
CREATE OR REPLACE FUNCTION mysql.connection_id()
RETURNS int
AS 'SELECT pg_catalog.pg_backend_pid()'
LANGUAGE SQL;

-- LAST_INSERT_ID()
CREATE OR REPLACE FUNCTION mysql.last_insert_id()
RETURNS int8
AS 'SELECT pg_catalog.lastval()'
LANGUAGE SQL;

-- ROW_COUNT() -- PG doesn't have a simple equivalent; use GET DIAGNOSTICS
-- This provides a placeholder that returns -1 (caller should use pg_catalog.ROW_COUNT via plpgsql)
CREATE OR REPLACE FUNCTION mysql.row_count()
RETURNS int8
AS $$
DECLARE
    rc int8;
BEGIN
    GET DIAGNOSTICS rc = ROW_COUNT;
    RETURN rc;
END;
$$ LANGUAGE plpgsql;

-- FOUND_ROWS()
CREATE OR REPLACE FUNCTION mysql.found_rows()
RETURNS int8
AS 'SELECT pg_catalog.mys_found_rows()'
LANGUAGE SQL;

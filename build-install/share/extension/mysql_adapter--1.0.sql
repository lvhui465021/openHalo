-- \echo mysql_adapter extension loading 1.0

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

CREATE DOMAIN mysql."bigint signed" AS pg_catalog.int8;
CREATE DOMAIN mysql."bigint unsigned" AS pg_catalog.int8 CHECK (0 <= VALUE);

CREATE DOMAIN mysql.real AS pg_catalog.float8;
CREATE DOMAIN mysql.double AS pg_catalog.float8;

CREATE DOMAIN mysql.datetime AS pg_catalog.timestamp;

CREATE DOMAIN mysql.binary AS pg_catalog.bytea;
CREATE DOMAIN mysql.varbinary AS pg_catalog.bytea;
CREATE DOMAIN mysql.blob AS pg_catalog.bytea;

CREATE DOMAIN mysql.year_ AS pg_catalog.int4 CHECK ((1901 <= VALUE) AND (VALUE <= 2155));

-- -----------------------------------------------------------------------------
-- Cast overrides: pg_catalog type casts for MySQL compatibility
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

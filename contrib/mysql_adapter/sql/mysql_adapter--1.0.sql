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
-- MySQL-compatible scalar functions
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

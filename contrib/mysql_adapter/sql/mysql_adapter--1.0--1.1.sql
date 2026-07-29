-- \echo mysql_adapter extension upgrading 1.0 -> 1.1

-- Keep upgrades self-contained: MySQL DDL lowering expects these collations
-- to be available through the mysql schema search-path entry.
CREATE COLLATION mysql.case_insensitive
    (provider = icu, locale = '@colStrength=secondary', deterministic = false);
CREATE COLLATION mysql.ignore_accents
    (provider = icu, locale = 'und-u-ks-level1-kc-true', deterministic = false);

-- -----------------------------------------------------------------------------
-- Domain fixes: complete CHECK constraints and add missing bare types
-- -----------------------------------------------------------------------------

-- KF-052: bigint unsigned missing upper-bound check
DO $$
DECLARE
    con_name text;
BEGIN
    SELECT conname INTO con_name
    FROM pg_catalog.pg_constraint
    WHERE contypid = 'mysql."bigint unsigned"'::regtype
    AND contype = 'c';
    IF FOUND THEN
        EXECUTE format('ALTER DOMAIN mysql."bigint unsigned" DROP CONSTRAINT %I', con_name);
    END IF;
END;
$$;
ALTER DOMAIN mysql."bigint unsigned" ADD CHECK ((0 <= VALUE) AND (VALUE <= 9223372036854775807));

-- KF-053: add bare INT / INTEGER domains (MySQL alias for INT SIGNED)
CREATE DOMAIN IF NOT EXISTS mysql.int AS pg_catalog.int4;
CREATE DOMAIN IF NOT EXISTS mysql.integer AS pg_catalog.int4;

-- -----------------------------------------------------------------------------
-- MySQL-compatible scalar functions: v1.1 string functions
-- -----------------------------------------------------------------------------

-- CONCAT(str1, str2, ...).  Unlike PostgreSQL concat(), MySQL returns NULL
-- whenever any argument is NULL.
CREATE OR REPLACE FUNCTION mysql.concat(VARIADIC text[])
RETURNS text
AS $$SELECT CASE WHEN array_position($1, NULL) IS NULL
                 THEN array_to_string($1, '')
            END$$
LANGUAGE SQL IMMUTABLE;

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
AS 'SELECT pg_catalog.upper(pg_catalog.to_hex($1))'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.hex(int4)
RETURNS text
AS 'SELECT pg_catalog.upper(pg_catalog.to_hex($1))'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.hex(bytea)
RETURNS text
AS 'SELECT pg_catalog.upper(pg_catalog.encode($1, ''hex''))'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.hex(text)
RETURNS text
AS 'SELECT pg_catalog.upper(pg_catalog.encode($1::bytea, ''hex''))'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.bin(int8)
RETURNS text
AS $$WITH RECURSIVE bits(value, result) AS (
         SELECT $1, ''::text
         UNION ALL
         SELECT value >> 1, result || (value & 1::int8)::text
         FROM bits WHERE value > 0
     )
     SELECT CASE WHEN $1 = 0 THEN '0' ELSE reverse(result) END
     FROM bits WHERE value = 0$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.bin(int4)
RETURNS text
AS 'SELECT mysql.bin($1::int8)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.bit_count(int8)
RETURNS int
AS $$SELECT count(*)::int
     FROM generate_series(0, 63) AS g(bit)
     WHERE ($1 & (1::int8 << bit)) <> 0$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.bit_count(int4)
RETURNS int
AS 'SELECT mysql.bit_count($1::int8)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.conv(text, int, int)
RETURNS text
AS $$WITH RECURSIVE parsed(position, value) AS (
         SELECT 1, 0::int8
         UNION ALL
         SELECT position + 1,
                value * $2 + strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                                    upper(substr($1, position, 1))) - 1
         FROM parsed
         WHERE position <= length($1)
     ), converted(value, result) AS (
         SELECT value, ''::text
         FROM parsed WHERE position = length($1) + 1
         UNION ALL
         SELECT value / $3,
                substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                       (value % $3)::int + 1, 1) || result
         FROM converted WHERE value > 0
     )
     SELECT CASE WHEN value = 0 AND result = '' THEN '0' ELSE result END
     FROM converted WHERE value = 0$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.ifnull(anycompatible, anycompatible)
RETURNS anycompatible
AS 'SELECT COALESCE($1, $2)'
LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.ifnull(int4, int4)
RETURNS int4
AS 'SELECT COALESCE($1, $2)'
LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.if(boolean, anycompatible, anycompatible)
RETURNS anycompatible
AS 'SELECT CASE WHEN $1 THEN $2 ELSE $3 END'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.if(int4, anycompatible, anycompatible)
RETURNS anycompatible
AS 'SELECT CASE WHEN $1 <> 0 THEN $2 ELSE $3 END'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.if(int4, text, text)
RETURNS text
AS 'SELECT CASE WHEN $1 <> 0 THEN $2 ELSE $3 END'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.isnull(anyelement)
RETURNS int
AS 'SELECT CASE WHEN $1 IS NULL THEN 1 ELSE 0 END'
LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.isnull(text)
RETURNS int
AS 'SELECT CASE WHEN $1 IS NULL THEN 1 ELSE 0 END'
LANGUAGE SQL IMMUTABLE;

-- Kept compatible with the UDB-TX PG16 implementation.  JSON values are
-- represented by PostgreSQL's json type, whose scalar-string text form is
-- quoted; remove that outer quoting for MySQL JSON_UNQUOTE().
CREATE OR REPLACE FUNCTION mysql.json_unquote(json)
RETURNS text
AS 'SELECT trim(''"'' FROM $1::text)'
LANGUAGE SQL;

-- INSTR(str, substr) -- returns position of first occurrence
CREATE OR REPLACE FUNCTION mysql.instr(text, text)
RETURNS int
AS $$
SELECT CASE WHEN $2 = '' THEN 1
            WHEN pg_catalog.strpos($1, $2) = 0 THEN 0
            ELSE pg_catalog.strpos($1, $2) END
$$
LANGUAGE SQL IMMUTABLE STRICT;

-- LEFT(str, len) and RIGHT(str, len)
CREATE OR REPLACE FUNCTION mysql.left(text, int)
RETURNS text
AS $$SELECT CASE WHEN $2 <= 0 THEN ''
                 ELSE pg_catalog.substr($1, 1, $2) END$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.right(text, int)
RETURNS text
AS $$SELECT CASE WHEN $2 <= 0 THEN ''
                 WHEN $2 >= pg_catalog.char_length($1) THEN $1
                 ELSE pg_catalog.substr($1, pg_catalog.char_length($1) - $2 + 1) END$$
LANGUAGE SQL IMMUTABLE STRICT;

-- SUBSTR(str, pos, len) uses one-based positions; negative positions count
-- backwards from the end, as in MySQL.
CREATE OR REPLACE FUNCTION mysql.substr(text, int, int)
RETURNS text
AS $$SELECT CASE WHEN $2 = 0 OR $3 <= 0 THEN ''
                 WHEN $2 > 0 THEN pg_catalog.substr($1, $2, $3)
                 ELSE pg_catalog.substr($1, pg_catalog.char_length($1) + $2 + 1, $3)
            END$$
LANGUAGE SQL IMMUTABLE STRICT;

-- LOCATE(substr, str [, pos])
CREATE OR REPLACE FUNCTION mysql.locate(text, text)
RETURNS int
AS 'SELECT mysql.locate($1, $2, 1)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.locate(text, text, int)
RETURNS int
AS $$SELECT CASE WHEN $3 <= 0 THEN 0
                 WHEN pg_catalog.strpos(pg_catalog.substr($2, $3), $1) = 0 THEN 0
                 ELSE $3 - 1 + pg_catalog.strpos(pg_catalog.substr($2, $3), $1)
            END$$
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

-- ELT(N, str1, str2, ...), FIELD(str, str1, str2, ...), and FIND_IN_SET.
CREATE OR REPLACE FUNCTION mysql.elt(int, VARIADIC text[])
RETURNS text
AS $$SELECT CASE WHEN $1 BETWEEN 1 AND cardinality($2) THEN $2[$1] END$$
LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.field(text, VARIADIC text[])
RETURNS int
AS $$SELECT COALESCE(array_position($2, $1), 0)$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.find_in_set(text, text)
RETURNS int
AS $$SELECT CASE WHEN $1 = '' THEN 0
                 ELSE COALESCE(array_position(string_to_array($2, ','), $1), 0)
            END$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.make_set(int8, VARIADIC text[])
RETURNS text
AS $$SELECT COALESCE(string_agg(value, ',' ORDER BY ordinality), '')
     FROM unnest($2) WITH ORDINALITY AS u(value, ordinality)
     WHERE ($1 & (1::int8 << ((ordinality - 1)::int))) <> 0$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.export_set(int8, text, text, text, int)
RETURNS text
AS $$SELECT string_agg(CASE WHEN ($1 & (1::int8 << (i::int))) <> 0 THEN $2 ELSE $3 END,
                            $4 ORDER BY i)
     FROM generate_series(0, GREATEST($5 - 1, 0)) AS g(i)$$
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.insert(text, int, int, text)
RETURNS text
AS $$SELECT CASE WHEN $2 < 1 OR $2 > char_length($1) THEN $1
                 ELSE substr($1, 1, $2 - 1) || $4 || substr($1, $2 + GREATEST($3, 0))
            END$$
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

-- PG16 UDB-TX supplies a text overload so an untyped MySQL date literal does
-- not ambiguously match date and timestamp overloads.  PG18's native
-- timestamp input accepts the ISO literal syntax used by MySQL clients.
CREATE OR REPLACE FUNCTION mysql.date_add(text, pg_catalog.interval)
RETURNS timestamp
AS 'SELECT $1::pg_catalog.timestamp + $2'
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

CREATE OR REPLACE FUNCTION mysql.date_sub(text, pg_catalog.interval)
RETURNS timestamp
AS 'SELECT $1::pg_catalog.timestamp - $2'
LANGUAGE SQL IMMUTABLE STRICT;

-- ADDDATE/SUBDATE are MySQL aliases with an integer-day form.  Retain the
-- PG16 text-first dispatch so bare literals select a single overload.
CREATE OR REPLACE FUNCTION mysql.adddate(text, integer)
RETURNS timestamp
AS 'SELECT $1::pg_catalog.timestamp + (''1 day''::pg_catalog.interval * $2)'
LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.subdate(text, integer)
RETURNS timestamp
AS 'SELECT $1::pg_catalog.timestamp - (''1 day''::pg_catalog.interval * $2)'
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

-- Match the PG16 compatibility overload used for untyped MySQL date
-- literals, while using PG18's native ISO date input conversion.
CREATE OR REPLACE FUNCTION mysql.datediff(text, text)
RETURNS int
AS 'SELECT $1::pg_catalog.date - $2::pg_catalog.date'
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

-- DATABASE() — returns the current MySQL database, which maps to the
-- first non-system schema in the PostgreSQL search_path.
CREATE OR REPLACE FUNCTION mysql.database()
RETURNS text
AS 'SELECT pg_catalog.current_schema()'
LANGUAGE SQL;

-- SCHEMA() — synonym for DATABASE() per MySQL semantics
CREATE OR REPLACE FUNCTION mysql.schema()
RETURNS text
AS 'SELECT pg_catalog.current_schema()'
LANGUAGE SQL;

-- USER()
CREATE OR REPLACE FUNCTION mysql.user()
RETURNS text
AS 'SELECT current_user'
LANGUAGE SQL;

-- CURRENT_USER() and SESSION_USER() are MySQL information functions as well
-- as SQL keywords.  Keep schema-qualified forms available to clients.
CREATE OR REPLACE FUNCTION mysql.current_user()
RETURNS text
AS '$libdir/mysm', 'getCurrentUser'
LANGUAGE C STABLE;

CREATE OR REPLACE FUNCTION mysql."session_user"()
RETURNS text
AS '$libdir/mysm', 'getSessionUser'
LANGUAGE C STABLE;

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
AS 'SELECT pg_catalog.mys_last_insert_id()'
LANGUAGE SQL;

-- ROW_COUNT() is tracked by the MySQL protocol completion path.
CREATE OR REPLACE FUNCTION mysql.row_count()
RETURNS int8
AS 'SELECT pg_catalog.mys_row_count()'
LANGUAGE SQL;

-- FOUND_ROWS()
CREATE OR REPLACE FUNCTION mysql.found_rows()
RETURNS int8
AS 'SELECT pg_catalog.mys_found_rows()'
LANGUAGE SQL;
-- PG16 UDB-TX DATE_FORMAT semantics, adapted to PG18's available week APIs.
CREATE OR REPLACE FUNCTION mysql.date_format(timestamp without time zone, text)
RETURNS text
AS
$$
DECLARE
    len int := pg_catalog.length($2);
    i int := 1;
    temp text := '';
    c text;
    n character;
    res text;
BEGIN
    WHILE i <= len LOOP
        c := substring($2 FROM i FOR 1);
        IF c = '%' AND i != len THEN
            n := (substring($2 FROM (i + 1) FOR 1))::character;
            SELECT INTO res CASE
                WHEN n = 'a' THEN pg_catalog.to_char($1, 'Dy')
                WHEN n = 'b' THEN pg_catalog.to_char($1, 'Mon')
                WHEN n = 'c' THEN pg_catalog.to_char($1, 'FMMM')
                WHEN n = 'D' THEN pg_catalog.to_char($1, 'FMDDth')
                WHEN n = 'd' THEN pg_catalog.to_char($1, 'DD')
                WHEN n = 'e' THEN pg_catalog.to_char($1, 'FMDD')
                WHEN n = 'f' THEN pg_catalog.to_char($1, 'US')
                WHEN n = 'H' THEN pg_catalog.to_char($1, 'HH24')
                WHEN n = 'h' THEN pg_catalog.to_char($1, 'HH12')
                WHEN n = 'I' THEN pg_catalog.to_char($1, 'HH12')
                WHEN n = 'i' THEN pg_catalog.to_char($1, 'MI')
                WHEN n = 'j' THEN pg_catalog.to_char($1, 'DDD')
                WHEN n = 'k' THEN pg_catalog.to_char($1, 'FMHH24')
                WHEN n = 'l' THEN pg_catalog.to_char($1, 'FMHH12')
                WHEN n = 'M' THEN pg_catalog.to_char($1, 'FMMonth')
                WHEN n = 'm' THEN pg_catalog.to_char($1, 'MM')
                WHEN n = 'p' THEN pg_catalog.to_char($1, 'AM')
                WHEN n = 'r' THEN pg_catalog.to_char($1, 'HH12:MI:SS AM')
                WHEN n = 'S' THEN pg_catalog.to_char($1, 'SS')
                WHEN n = 's' THEN pg_catalog.to_char($1, 'SS')
                WHEN n = 'T' THEN pg_catalog.to_char($1, 'HH24:MI:SS')
                WHEN n = 'U' THEN pg_catalog.lpad(mysql.week($1::date, 0)::text, 2, '0')
                WHEN n = 'u' THEN pg_catalog.lpad(mysql.week($1::date, 1)::text, 2, '0')
                WHEN n = 'V' THEN pg_catalog.lpad(mysql.week($1::date, 2)::text, 2, '0')
                WHEN n = 'v' THEN pg_catalog.lpad(mysql.week($1::date, 3)::text, 2, '0')
                WHEN n = 'W' THEN pg_catalog.to_char($1, 'FMDay')
                WHEN n = 'w' THEN EXTRACT(DOW FROM $1)::text
                WHEN n = 'X' THEN pg_catalog.lpad(((_calc_mysql.week($1::date, _week_mode(2)))[2])::text, 4, '0')
                WHEN n = 'x' THEN pg_catalog.lpad(((_calc_mysql.week($1::date, _week_mode(3)))[2])::text, 4, '0')
                WHEN n = 'Y' THEN pg_catalog.to_char($1, 'YYYY')
                WHEN n = 'y' THEN pg_catalog.to_char($1, 'YY')
                WHEN n = '%' THEN pg_catalog.to_char($1, '%')
                ELSE NULL
            END;

            if res is not null then
                temp := temp operator(pg_catalog.||) res;
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            temp := temp operator(pg_catalog.||) c;
            i := i + 1;
        END IF;
    END LOOP;
    RETURN temp;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.date_format(text, text)
RETURNS text
AS $$SELECT mysql.date_format($1::timestamp without time zone, $2)$$
LANGUAGE SQL IMMUTABLE STRICT;

-- PG16 UDB-TX system-variable catalogue.  The backend system-variable
-- implementation reads this relation during MySQL parser initialization.
create table mys_informa_schema.base_variables(
    variable_name varchar(128),
    def_value varchar(1024),
    conf_value varchar(1024),
    sess_global_type int,
    -- sess_global_type 0: global & session, 1:global only, 2:session only, 3:session only but can select global
    sess_def_val_from_global bool,
    is_read_write bool,
    valid_result varchar(256),
    select_result_rule varchar(256),
    show_result_rule varchar(256),
    primary key(variable_name)
);
insert into mys_informa_schema.base_variables values('autocommit', '1', '1', 0, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('auto_increment_increment', '1', '1', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('auto_increment_offset', '1', '1', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('big_tables', '0', '0', 0, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('character_set_client', 'utf8mb4', 'utf8mb4', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('character_set_connection', 'utf8mb4', 'utf8mb4', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('character_set_results', 'utf8mb4', 'utf8mb4', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('character_set_server', 'utf8mb4', 'utf8mb4', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('character_set_database', 'utf8mb4', 'utf8mb4', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('collation_connection', 'utf8mb4_general_ci', 'utf8mb4_general_ci', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('collation_server', 'utf8mb4_general_ci', 'utf8mb4_general_ci', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('default_storage_engine', 'InnoDB', 'InnoDB', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('enforce_gtid_consistency', '0', '0', 1, true, true, '0|1', 'OFF|ON', 'OFF|ON');
insert into mys_informa_schema.base_variables values('explicit_defaults_for_timestamp', '0', '1', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('foreign_key_checks', '1', '1', 0, false, true, null, null, null);
insert into mys_informa_schema.base_variables values('ft_max_word_len', '84', '84', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('have_profiling', 'YES', 'YES', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('init_connect', '', '', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_chunk_size', '134217728', '134217728', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_dump_at_shutdown', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_dump_now', '0', '0', 1, false, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_dump_pct', '25', '25', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_filename', 'ib_buffer_pool', 'ib_buffer_pool', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_instances', '8', '8', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_load_abort', '0', '0', 1, false, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_load_at_startup', '1', '1', 1, true, false, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_load_now', '0', '0', 1, false, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('innodb_buffer_pool_size', '1073741824', '1073741824', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_checksums', '1', '1', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_flush_log_at_trx_commit', '1', '2', 1, true, true, '0|1|2', '0|1|2', '0|1|2');
insert into mys_informa_schema.base_variables values('innodb_log_buffer_size', '2097152', '2097152', 1, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_log_file_size', '33554432', '33554432', 1, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_log_files_in_group', '3', '3', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_sort_buffer_size', '1048576', '1048576', 1, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_strict_mode', '1', '1', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_thread_concurrency', '0', '0', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_thread_sleep_delay', '10000', '10000', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('interactive_timeout', '28800', '20000', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('join_buffer_size', '262144', '8388608', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('last_insert_id', '0', '0', 2, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('license', 'GPL', 'GPL', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('long_query_time', '10', '10', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('lower_case_file_system', '0', '0', 0, true, false, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('lower_case_table_names', '1', '1', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('max_allowed_packet', '4194304', '536870912', 1, false, true, null, null, null);
insert into mys_informa_schema.base_variables values('max_connections', '151', '100', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('max_length_for_sort_data', '1024', '1024', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('max_seeks_for_key', '18446744073709551615', '18446744073709551615', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('max_sp_recursion_depth', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('max_user_connections', '0', '0', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('myisam_sort_buffer_size', '8388608', '8388608', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('myisam_stats_method', '0', '0', 0, true, true, '0|1|2', 'nulls_unequal|nulls_equal|nulls_ignored', 'nulls_unequal|nulls_equal|nulls_ignored');
insert into mys_informa_schema.base_variables values('net_buffer_length', '16384', '16384', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('net_write_timeout', '60', '60', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('optimizer_prune_level', '1', '1', 0, true, true, '0|1', null, '0|1');
insert into mys_informa_schema.base_variables values('optimizer_switch', 'index_merge=on,index_merge_union=on,index_merge_sort_union=on,index_merge_intersection=on,engine_condition_pushdown=on,index_condition_pushdown=on,mrr=on,mrr_cost_based=on,block_nested_loop=on,batched_key_access=off,materialization=on,semijoin=on,loosescan=on,firstmatch=on,duplicateweedout=on,subquery_materialization_cost_based=on,use_index_extensions=on,condition_fanout_filter=on,derived_merge=on', 'index_merge=on,index_merge_union=on,index_merge_sort_union=on,index_merge_intersection=on,engine_condition_pushdown=on,index_condition_pushdown=on,mrr=on,mrr_cost_based=on,block_nested_loop=on,batched_key_access=off,materialization=on,semijoin=on,loosescan=on,firstmatch=on,duplicateweedout=on,subquery_materialization_cost_based=on,use_index_extensions=on,condition_fanout_filter=on,derived_merge=on', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('parser_max_mem_size', '18446744073709551615', '18446744073709551615', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('performance_schema', '0', '0', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('profiling_history_size', '15', '15', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('profiling', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('query_cache_limit', '1048576', '1048576', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('query_cache_min_res_unit', '4096', '4096', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('query_cache_size', '1048576', '1048576', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('query_cache_type', '0', '1', 0, true, true, '0|1|2', 'OFF|ON|DEMAND', 'OFF|ON|DEMAND');
insert into mys_informa_schema.base_variables values('query_cache_wlock_invalidate', '0', '1', 0, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('range_alloc_block_size', '4096', '4096', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('range_optimizer_max_mem_size', '8388608', '8388608', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('rbr_exec_mode', '0', '0', 3, true, true, '0|1', 'STRICT|IDEMPOTENT', 'STRICT|IDEMPOTENT');
insert into mys_informa_schema.base_variables values('read_buffer_size', '131072', '2097152', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('require_secure_transport', '0', '0', 1, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('secure_file_priv', '', '', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('session_track_gtids', '0', '0', 0, true, true, '0|1|2', 'OFF|OWN_GTID|ALL_GTIDS', 'OFF|OWN_GTID|ALL_GTIDS');
insert into mys_informa_schema.base_variables values('session_track_schema', '1', '1', 0, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('session_track_state_change', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('session_track_system_variables', 'time_zone,autocommit,character_set_client,character_set_results,character_set_connection', 'time_zone,autocommit,character_set_client,character_set_results,character_set_connection', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('session_track_transaction_info', '0', '0', 0, true, true, '0|1', 'OFF|ON', 'OFF|ON');
insert into mys_informa_schema.base_variables values('show_create_table_verbosity', '0', '0', 0, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('sort_buffer_size', '262144', '8388608', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sql_auto_is_null', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sql_mode', 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION', 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sql_notes', '1', '1', 0, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('sql_quote_show_create', '1', '1', 0, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('sql_safe_updates', '0', '0', 0, true, true, '0|1', null, 'OFF|ON');
insert into mys_informa_schema.base_variables values('sql_select_limit', '18446744073709551615', '18446744073709551615', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('system_time_zone', 'CST', 'CST', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('thread_cache_size', '9', '8', 1, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('time_zone', 'SYSTEM', 'SYSTEM', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('transaction_isolation', 'REPEATABLE-READ', 'REPEATABLE-READ', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('transaction_read_only', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('tx_isolation', 'REPEATABLE-READ', 'REPEATABLE-READ', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('tx_read_only', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('unique_checks', 'on', 'on', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('version_comment', 'MySQL Server (GPL)', 'MySQL Server (GPL)', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('wait_timeout', '28800', '20000', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_default_row_format', '2', '2', 1, true, true, '0|1|2|3', 'redundant|compact|dynamic|compressed', 'redundant|compact|dynamic|compressed');
insert into mys_informa_schema.base_variables values('innodb_file_format', '1', '1', 1, true, true, '0|1', 'Antelope|Barracuda', 'Antelope|Barracuda');
insert into mys_informa_schema.base_variables values('innodb_file_format_check', '1', '1', 0, true, false, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('innodb_file_format_max', '0', '1', 1, true, true, '0|1', 'Antelope|Barracuda', 'Antelope|Barracuda');
insert into mys_informa_schema.base_variables values('innodb_file_per_table', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('collation_database', 'utf8mb4_general_ci', 'utf8mb4_general_ci', 0, true, true, null, null, null);
INSERT INTO mys_informa_schema.base_variables VALUES ('datadir', '/data/unvdb/', '/data/unvdb/', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('unvdb_mysql_dummy_stmt_return_ok', '1', '1', 0, true, true, '0|1', '0|1', '0|1');
insert into mys_informa_schema.base_variables values('have_query_cache', '1', '1', 1, true, false, '0|1', 'NO|YES', 'NO|YES');
insert into mys_informa_schema.base_variables values('automatic_sp_privileges', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('check_proxy_users', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('completion_type', '0', '0', 1, true, true, '0|1|2', 'NO_CHAIN|CHAIN|RELEASE', 'NO_CHAIN|CHAIN|RELEASE');
insert into mys_informa_schema.base_variables values('concurrent_insert', '1', '1', 1, true, true, '0|1|2', 'NEVER|AUTO|ALWAYS', 'NEVER|AUTO|ALWAYS');
insert into mys_informa_schema.base_variables values('connect_timeout', '10', '10', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('core_file', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('default_authentication_plugin', '0', '0', 1, true, true, '0|1', 'mysql_native_password|sha256_password', 'mysql_native_password|sha256_password');
insert into mys_informa_schema.base_variables values('default_password_lifetime', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('default_tmp_storage_engine', '0', '0', 1, true, true, '0|1|2|3|4|5|6|7', 'InnoDB|MRG_MYISAM|MyISAM|BLACKHOLE|CSV|mem|ARCHIVE|FEDERATED', 'InnoDB|MRG_MYISAM|MyISAM|BLACKHOLE|CSV|mem|ARCHIVE|FEDERATED');
insert into mys_informa_schema.base_variables values('default_week_format', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('disabled_storage_engines', '0', '0', 1, true, true, '0|1', '0|1', ' | ');
insert into mys_informa_schema.base_variables values('disconnect_on_expired_password', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('block_encryption_mode', '0', '0', 1, true, true, '0|1|2|3|4|5', 'aes-128-ecb|aes-192-ecb|aes-256-ecb|aes-128-cbc|aes-192-cbc|aes-256-cbc', 'aes-128-ecb|aes-192-ecb|aes-256-ecb|aes-128-cbc|aes-192-cbc|aes-256-cbc');
insert into mys_informa_schema.base_variables values('bulk_insert_buffer_size', '8388608', '8388608', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('binlog_cache_size', '1048576', '1048576', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('binlog_checksum', '1', '1', 1, true, true, '0|1', 'NONE|CRC32', 'NONE|CRC32');
insert into mys_informa_schema.base_variables values('binlog_error_action', '1', '1', 1, true, true, '0|1', 'IGNORE_ERROR|ABORT_SERVER', 'IGNORE_ERROR|ABORT_SERVER');
insert into mys_informa_schema.base_variables values('binlog_format', '1', '1', 1, true, true, '0|1|2', 'STATEMENT|ROW|MIXED', 'STATEMENT|ROW|MIXED');
insert into mys_informa_schema.base_variables values('binlog_group_commit_sync_delay', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('binlog_group_commit_sync_no_delay_count', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('binlog_gtid_simple_recovery', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('binlog_order_commits', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('binlog_row_image', '0', '0', 1, true, true, '0|1|2', 'FULL|MINIMAL|NOBLOB', 'FULL|MINIMAL|NOBLOB');
insert into mys_informa_schema.base_variables values('binlog_rows_query_log_events', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('binlog_stmt_cache_size', '32768', '32768', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('character_set_filesystem', '0', '0', 1, true, true, '0|1|2', 'binary|utf8|ascii', 'binary|utf8|ascii');
insert into mys_informa_schema.base_variables values('character_set_system', '1', '1', 1, true, true, '0|1|2', 'binary|utf8|ascii', 'binary|utf8|ascii');
INSERT INTO mys_informa_schema.base_variables VALUES('character_sets_dir', '/data/unvdb/', '/data/unvdb/', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('delay_key_write', '0', '0', 1, true, true, '0|1|2', 'ON|OFF|ALL', 'ON|OFF|ALL');
insert into mys_informa_schema.base_variables values('div_precision_increment', '4', '4', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('end_markers_in_json', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('eq_range_index_dive_limit', '200', '200', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('event_scheduler', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('expire_logs_days', '1', '1', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('flush', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('flush_time', '0', '0', 0, true, true, null, null, null);
INSERT INTO mys_informa_schema.base_variables VALUES('ft_boolean_syntax', '+ -&gt;&lt;()~*:""&amp;|', '+ -&gt;&lt;()~*:""&amp;|', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('ft_min_word_len', '4', '4', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('ft_query_expansion_limit', '20', '20', 0, true, true, null, null, null);
INSERT INTO mys_informa_schema.base_variables VALUES('ft_stopword_file', '(built-in)', '(built-in)', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('general_log', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
INSERT INTO mys_informa_schema.base_variables VALUES('general_log_file', '/var/lib/mysql/data/hostname.log', '/var/lib/mysql/data/hostname.log', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('group_concat_max_len', '1024', '1024', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('gtid_executed_compression_period', '1000', '1000', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('gtid_mode', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
INSERT INTO mys_informa_schema.base_variables VALUES('gtid_next', 'AUTOMATIC', 'AUTOMATIC', 0, true, false, null, null, null);
INSERT INTO mys_informa_schema.base_variables VALUES('gtid_owned', '', '', 0, true, false, null, null, null);
INSERT INTO mys_informa_schema.base_variables VALUES('gtid_purged', '', '', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('host_cache_size', '228', '228', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('internal_tmp_disk_storage_engine', '0', '0', 1, true, true, '0|1', 'INNODB|MYISAM', 'INNODB|MYISAM');
insert into mys_informa_schema.base_variables values('keep_files_on_create', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('key_buffer_size', '4194304', '4194304', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('updatable_views_with_limit', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|YES');
insert into mys_informa_schema.base_variables values('thread_handling', '0', '0', 1, true, true, '0|1|2', 'one-thread-per-connection|one-thread-for-all-connections|pool-of-threads', 'one-thread-per-connection|one-thread-for-all-connections|pool-of-threads');
insert into mys_informa_schema.base_variables values('thread_stack', '262144', '262144', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('tmp_table_size', '16777216', '16777216', 0, true, true, null, null, null);
INSERT INTO mys_informa_schema.base_variables VALUES('tmpdir', '/tmp', '/tmp', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('transaction_alloc_block_size', '8192', '8192', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('transaction_prealloc_size', '4096', '4096', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('transaction_write_set_extraction', '0', '0', 1, true, true, '0|1|2', 'OFF|MURMUR32|XXHASH6', 'OFF|MURMUR32|XXHASH6');
insert into mys_informa_schema.base_variables values('table_definition_cache', '464', '464', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('table_open_cache', '128', '128', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('table_open_cache_instances', '16', '16', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sync_binlog', '1', '1', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sync_master_info', '10000', '10000', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sync_relay_log', '10000', '10000', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sync_relay_log_info', '10000', '10000', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sync_frm', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('super_read_only', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('stored_program_cache', '256', '256', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sql_big_selects', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('sql_buffer_result', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('sql_log_bin', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('sql_log_off', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('sql_slave_skip_counter', '0', '0', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('sql_warnings', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
INSERT INTO mys_informa_schema.base_variables VALUES('socket', '/tmp/mysql.sock', '/tmp/mysql.sock', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('slow_launch_time', '2', '2', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('slow_query_log', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
INSERT INTO mys_informa_schema.base_variables VALUES('slow_query_log_file', '/var/lib/mysql/data/slow.log', '/var/lib/mysql/data/slow.log', 0, true, false, null, null, null);
insert into mys_informa_schema.base_variables values('skip_external_locking', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('skip_name_resolve', '1', '1', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('skip_networking', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('skip_show_database', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('show_compatibility_56', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('sha256_password_proxy_users', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('server_id', '1', '1', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('server_id_bits', '32', '32', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('read_only', '0', '0', 1, true, true, '0|1', '0|1', 'OFF|ON');
insert into mys_informa_schema.base_variables values('read_rnd_buffer_size', '8388608', '8388608', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('query_alloc_block_size', '8192', '8192', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('query_prealloc_size', '8192', '8192', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('preload_buffer_size', '32768', '32768', 0, true, true, null, null, null);
insert into mys_informa_schema.base_variables values('innodb_lock_wait_timeout', '50', '50', 0, true, true, null, null, null);

-- -----------------------------------------------------------------------------
-- Additional mys_informa_schema views (v1.1)
-- -----------------------------------------------------------------------------

-- View: mys_informa_schema.routines
CREATE OR REPLACE VIEW mys_informa_schema.routines AS
SELECT n.nspname AS routine_schema,
       p.proname AS routine_name
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace;

-- View: mys_informa_schema.views
CREATE OR REPLACE VIEW mys_informa_schema.views AS
SELECT n.nspname AS table_schema,
       c.relname AS table_name
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'v';

-- View: mys_informa_schema.indexs
CREATE OR REPLACE VIEW mys_informa_schema.indexs AS
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       c2.relname AS index_name,
       i.indisunique AS is_unique,
       i.indisprimary AS is_primary,
       am.amname AS index_type
FROM pg_catalog.pg_index i
JOIN pg_catalog.pg_class c ON c.oid = i.indrelid
JOIN pg_catalog.pg_class c2 ON c2.oid = i.indexrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_am am ON am.oid = c2.relam
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast');

-- Fix mys_informa_schema.views: add table_type column
DROP VIEW IF EXISTS mys_informa_schema.views;
CREATE OR REPLACE VIEW mys_informa_schema.views AS
SELECT n.nspname AS table_schema,
       c.relname AS table_name,
       'VIEW'::varchar(256) AS table_type
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'v';

-- Fix mys_informa_schema.indexs: add key_name alias
DROP VIEW IF EXISTS mys_informa_schema.indexs;
CREATE OR REPLACE VIEW mys_informa_schema.indexs AS
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       c2.relname AS index_name,
       c2.relname AS key_name,
       i.indisunique AS is_unique,
       i.indisprimary AS is_primary,
       am.amname AS index_type
FROM pg_catalog.pg_index i
JOIN pg_catalog.pg_class c ON c.oid = i.indrelid
JOIN pg_catalog.pg_class c2 ON c2.oid = i.indexrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_am am ON am.oid = c2.relam
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast');

-- -----------------------------------------------------------------------------
-- MySQL metadata query functions (v1.1)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mysql.show_table_columns(pg_catalog.text, pg_catalog.text) RETURNS SETOF RECORD AS $$
DECLARE
    sch_oid pg_catalog.Oid; tab_oid pg_catalog.Oid; rec RECORD;
BEGIN
    IF $1 IS NOT NULL THEN SELECT oid INTO sch_oid FROM pg_catalog.pg_namespace WHERE nspname = $1;
    ELSE SELECT oid INTO sch_oid FROM pg_catalog.pg_namespace WHERE nspname = pg_catalog.current_schema(); END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid schema name: %', $1; END IF;
    SELECT oid INTO tab_oid FROM pg_catalog.pg_class WHERE relname = $2 AND relnamespace = sch_oid AND oid >= 16384;
    IF NOT FOUND THEN RAISE EXCEPTION 'Table %.% does not exist', $1, $2; END IF;
    FOR rec IN
        SELECT a.attname::varchar(256) AS "Field", pg_catalog.format_type(a.atttypid, a.atttypmod)::varchar(64) AS "Type",
            CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END::varchar(8) AS "Null",
            CASE WHEN pk.attname IS NOT NULL THEN 'PRI' WHEN uq.attname IS NOT NULL THEN 'UNI' WHEN ix.attname IS NOT NULL THEN 'MUL' ELSE '' END::varchar(256) AS "Key",
            pg_catalog.pg_get_expr(d.adbin, d.adrelid)::text AS "Default",
            CASE WHEN pg_catalog.pg_get_expr(d.adbin, d.adrelid) LIKE 'nextval%' THEN 'auto_increment' ELSE '' END::varchar(256) AS "Extra"
        FROM pg_catalog.pg_attribute a
        LEFT JOIN pg_catalog.pg_attrdef d ON (d.adrelid = a.attrelid AND d.adnum = a.attnum)
        LEFT JOIN (SELECT ia.attname FROM pg_catalog.pg_index i JOIN pg_catalog.pg_attribute ia ON ia.attrelid = i.indrelid AND ia.attnum = ANY(i.indkey) WHERE i.indisprimary AND i.indrelid = tab_oid LIMIT 1) pk ON pk.attname = a.attname
        LEFT JOIN (SELECT ia.attname FROM pg_catalog.pg_index i JOIN pg_catalog.pg_attribute ia ON ia.attrelid = i.indrelid AND ia.attnum = ANY(i.indkey) WHERE i.indisunique AND NOT i.indisprimary AND i.indrelid = tab_oid LIMIT 1) uq ON uq.attname = a.attname AND pk.attname IS NULL
        LEFT JOIN (SELECT ia.attname FROM pg_catalog.pg_index i JOIN pg_catalog.pg_attribute ia ON ia.attrelid = i.indrelid AND ia.attnum = ANY(i.indkey) WHERE NOT i.indisunique AND i.indrelid = tab_oid LIMIT 1) ix ON ix.attname = a.attname AND pk.attname IS NULL AND uq.attname IS NULL
        WHERE a.attrelid = tab_oid AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum
    LOOP RETURN NEXT rec; END LOOP; RETURN;
END; $$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION mysql.show_table_indexs(pg_catalog.text, pg_catalog.text) RETURNS SETOF RECORD AS $$
DECLARE
    sch_oid pg_catalog.Oid; tab_oid pg_catalog.Oid; rec RECORD; idx_rec RECORD;
    keys pg_catalog.int2[]; key_idx pg_catalog.int4; seq_num pg_catalog.int4; col_name pg_catalog.text;
BEGIN
    IF $1 IS NOT NULL THEN SELECT oid INTO sch_oid FROM pg_catalog.pg_namespace WHERE nspname = $1;
    ELSE SELECT oid INTO sch_oid FROM pg_catalog.pg_namespace WHERE nspname = pg_catalog.current_schema(); END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'Table %.% does not exist', $1, $2; END IF;
    SELECT oid INTO tab_oid FROM pg_catalog.pg_class WHERE relname = $2 AND relnamespace = sch_oid AND oid >= 16384;
    IF NOT FOUND THEN RAISE EXCEPTION 'Table %.% does not exist', $1, $2; END IF;
    FOR idx_rec IN SELECT ic.relname AS index_name, i.indisunique, i.indisprimary, i.indkey, am.amname AS index_type
        FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class ic ON ic.oid = i.indexrelid JOIN pg_catalog.pg_am am ON am.oid = ic.relam WHERE i.indrelid = tab_oid
    LOOP
        keys := idx_rec.indkey; seq_num := 1;
        FOR key_idx IN 1..array_length(keys, 1) LOOP
            SELECT attname INTO col_name FROM pg_catalog.pg_attribute WHERE attrelid = tab_oid AND attnum = keys[key_idx];
            SELECT (SELECT c.relname FROM pg_catalog.pg_class c WHERE c.oid = tab_oid)::varchar(256),
                CASE WHEN idx_rec.indisunique THEN 0 ELSE 1 END,
                CASE WHEN idx_rec.indisprimary THEN 'PRIMARY' ELSE idx_rec.index_name END::varchar(256),
                seq_num, col_name::varchar(256), 'A'::varchar(256), 0, NULL::int4, NULL::varchar(256), ''::varchar(8),
                idx_rec.index_type::varchar(256), ''::varchar(512), ''::varchar(512) INTO rec;
            RETURN NEXT rec; seq_num := seq_num + 1;
        END LOOP;
    END LOOP; RETURN;
END; $$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION mysql.timestampadd(text, integer, timestamp without time zone) RETURNS timestamp without time zone
AS $$ SELECT CASE lower($1) WHEN 'second' THEN $3 + ($2 || ' seconds')::interval WHEN 'minute' THEN $3 + ($2 || ' minutes')::interval WHEN 'hour' THEN $3 + ($2 || ' hours')::interval WHEN 'day' THEN $3 + ($2 || ' days')::interval WHEN 'week' THEN $3 + ($2 * 7 || ' days')::interval WHEN 'month' THEN $3 + ($2 || ' months')::interval WHEN 'quarter' THEN $3 + ($2 * 3 || ' months')::interval WHEN 'year' THEN $3 + ($2 || ' years')::interval ELSE $3 + ($2 || ' days')::interval END $$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.str_to_date(text, text) RETURNS timestamp without time zone
AS $$ BEGIN RETURN $1::timestamp without time zone; EXCEPTION WHEN OTHERS THEN RETURN NULL; END; $$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- _week_mode
CREATE OR REPLACE FUNCTION mysql._week_mode(integer) RETURNS integer AS $$
DECLARE _WEEK_MONDAY_FIRST CONSTANT integer := 1; _WEEK_FIRST_WEEKDAY CONSTANT integer := 4;
week_format integer := $1 & 7;
BEGIN IF (week_format & _WEEK_MONDAY_FIRST)=0 THEN week_format := week_format # _WEEK_FIRST_WEEKDAY; END IF;
RETURN week_format; END; $$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

-- show_create_view
CREATE OR REPLACE FUNCTION mysql.show_create_view(text, text) RETURNS SETOF RECORD AS $$
DECLARE rec RECORD; found bool := false;
BEGIN FOR rec IN SELECT $2::varchar(64) AS "View",
    'CREATE ALGORITHM=UNDEFINED DEFINER='||COALESCE(v.viewowner,'unknown')||E'@% SQL SECURITY DEFINER VIEW `'||$2||'` AS '||v.definition AS "Create View",
    'utf8mb4'::varchar(128) AS character_set_client, 'utf8mb4_general_ci'::varchar(128) AS collation_connection
    FROM pg_views v WHERE v.schemaname=$1 AND v.viewname=$2
LOOP found:=true; RETURN NEXT rec; END LOOP;
IF NOT found THEN RAISE EXCEPTION 'VIEW %.% does not exist', $1, $2; END IF; RETURN; END;
$$ LANGUAGE plpgsql STABLE;

-- show_create_table
CREATE OR REPLACE FUNCTION mysql.show_create_table(text, text) RETURNS SETOF RECORD AS $$
DECLARE sch_oid oid; tab_oid oid; rec RECORD; is_v bool:=false; col_defs text:=''; col RECORD;
BEGIN
    SELECT oid INTO sch_oid FROM pg_namespace WHERE nspname=$1;
    IF NOT FOUND OR sch_oid=0 THEN RAISE EXCEPTION 'Table %.% does not exist', $1, $2; END IF;
    PERFORM 1 FROM pg_views WHERE schemaname=$1 AND viewname=$2;
    IF FOUND THEN FOR rec IN SELECT * FROM mysql.show_create_view($1,$2)
        AS ("View" varchar(64),"Create View" text,character_set_client varchar(128),collation_connection varchar(128))
    LOOP RETURN NEXT rec; END LOOP; RETURN; END IF;
    SELECT oid INTO tab_oid FROM pg_class WHERE relname=$2 AND relnamespace=sch_oid AND oid>=16384;
    IF NOT FOUND OR tab_oid=0 THEN RAISE EXCEPTION 'Table %.% does not exist', $1, $2; END IF;
    FOR col IN SELECT a.attname, format_type(a.atttypid,a.atttypmod) AS col_type,
        CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END AS nullable,
        COALESCE(' DEFAULT '||pg_get_expr(d.adbin,d.adrelid),'') AS default_val
        FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid=tab_oid AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum
    LOOP IF col_defs!='' THEN col_defs:=col_defs||E',\n  '; END IF;
        col_defs:=col_defs||'  `'||col.attname||'` '||col.col_type||col.nullable||col.default_val;
    END LOOP;
    SELECT $2::varchar(64) AS "Table",
        'CREATE TABLE `'||$2||'` (\n'||col_defs||E'\n) ENGINE=InnoDB' AS "Create Table" INTO rec;
    RETURN NEXT rec; RETURN;
END; $$ LANGUAGE plpgsql STABLE;

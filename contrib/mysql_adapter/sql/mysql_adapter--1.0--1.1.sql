-- \echo mysql_adapter extension upgrading 1.0 -> 1.1

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

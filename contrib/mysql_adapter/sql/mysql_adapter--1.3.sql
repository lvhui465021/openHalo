
CREATE SCHEMA IF NOT EXISTS mysql;
GRANT USAGE ON SCHEMA mysql TO PUBLIC;

CREATE SCHEMA IF NOT EXISTS mys_informa_schema;
GRANT USAGE ON SCHEMA mys_informa_schema TO PUBLIC;

CREATE SCHEMA IF NOT EXISTS performance_schema;
GRANT USAGE ON SCHEMA performance_schema TO PUBLIC;

CREATE SCHEMA IF NOT EXISTS sys;
GRANT USAGE ON SCHEMA sys TO PUBLIC;

CREATE SCHEMA IF NOT EXISTS mys_sys;
GRANT USAGE ON SCHEMA mys_sys TO PUBLIC;


create domain mysql.tinyint as pg_catalog.int2 check((-128 <= value) and (VALUE <= 127));
create domain mysql."tinyint signed" as pg_catalog.int2 check((-128 <= value) and (VALUE <= 127));
create domain mysql."tinyint unsigned" as pg_catalog.int2 check((0 <= value) and (VALUE <= 255));
create domain mysql.tinyint1 as pg_catalog.int2 check((-128 <= value) and (VALUE <= 127));
create domain mysql."tinyint1 signed" as pg_catalog.int2 check((-128 <= value) and (VALUE <= 127));
create domain mysql."tinyint1 unsigned" as pg_catalog.int2 check((0 <= value) and (VALUE <= 255));
create domain mysql.smallint as pg_catalog.int2;
create domain mysql."smallint signed" as pg_catalog.int2;
create domain mysql."smallint unsigned" as pg_catalog.int4 check((0 <= value) and (VALUE <= 65535));
create domain mysql.mediumint as pg_catalog.int4 check((-8388608 <= value) and (VALUE <= 8388607));
create domain mysql."mediumint signed" as pg_catalog.int4 check((-8388608 <= value) and (VALUE <= 8388607));
create domain mysql."mediumint unsigned" as pg_catalog.int4 check((0 <= VALUE) and (VALUE <= 16777215));
--create domain mysql.int as pg_catalog.int4;
create domain mysql."int signed" as pg_catalog.int4;
create domain mysql."int unsigned" as pg_catalog.int8 check((0 <= VALUE) and (VALUE <= 4294967295));
--create domain mysql.bigint as pg_catalog.int8;
create domain mysql."bigint signed" as pg_catalog.int8;
create domain mysql."bigint unsigned" as pg_catalog.int8 check(0 <= VALUE);
-- create domain mysql.char as pg_catalog.bpchar;
-- create domain mysql.varchar as pg_catalog.varchar;
create domain mysql.real as pg_catalog.float8;
create domain mysql.double as pg_catalog.float8;
create domain mysql.datetime as pg_catalog.timestamp;
--create domain mysql.tinytext as pg_catalog.text;
--create domain mysql.text as pg_catalog.text;
--create domain mysql."text byte" as pg_catalog.bytea;
--create domain mysql.mediumtext as pg_catalog.text;
--create domain mysql.longtext as pg_catalog.text;
create domain mysql.binary as pg_catalog.bytea;
create domain mysql.varbinary as pg_catalog.bytea;
--create domain mysql.bit as pg_catalog.bytea;
--create domain mysql.tinyblob as pg_catalog.bytea;
create domain mysql.blob as pg_catalog.bytea;
--create domain mysql.mediumblob as pg_catalog.bytea;
--create domain mysql.longblob as pg_catalog.bytea;
create domain mysql.year_ as pg_catalog.int4 check((1901 <= VALUE) and (VALUE <= 2155));


update pg_cast set castcontext = 'i' where castsource = 23 and casttarget = 16;
update pg_cast set castcontext = 'a' where castsource = 16 and casttarget = 23;

create or replace function mysql.cast_boolean_to_tinyint(pg_catalog.bool) 
returns int2
as 
$$
begin
    if $1 then
        return 1;
    else
        return 0;
    end if;
end;
$$ 
language 'plpgsql' strict; 
create cast (pg_catalog.bool as int2) with function mysql.cast_boolean_to_tinyint as assignment;

create or replace function mysql.cast_boolean_to_bigint(pg_catalog.bool) 
returns int8
as 
$$
begin
    if $1 then
        return 1;
    else
        return 0;
    end if;
end;
$$ 
language 'plpgsql' strict; 
create cast (pg_catalog.bool as int8) with function mysql.cast_boolean_to_bigint as assignment;

CREATE OR REPLACE FUNCTION mysql.cast_bittext_to_bytea(text)
RETURNS bytea
AS '$libdir/mysm', 'cast_bittext_to_bytea'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.cast_bit_to_bytea(bit)
RETURNS bytea
as 
$$
BEGIN
    return mysql.cast_bittext_to_bytea($1::text);
END; 
$$ 
language 'plpgsql'; 
create cast (pg_catalog.bit as pg_catalog.bytea) with function mysql.cast_bit_to_bytea as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.interval(text, integer)
RETURNS pg_catalog.interval
LANGUAGE c
IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/mysm', $function$text_interval$function$;
CREATE CAST(text as pg_catalog.interval) with function mysql.interval(text, integer) as implicit;

CREATE OR REPLACE FUNCTION mysql.bit_to_text(pg_catalog.bit)
RETURNS text
AS '$libdir/mysm', 'mys_bit_to_text'
LANGUAGE C STRICT IMMUTABLE;
create cast (pg_catalog.bit as text) with function mysql.bit_to_text as ASSIGNMENT;

DROP CAST IF EXISTS(pg_catalog.bit as bytea);
DROP FUNCTION IF EXISTS mysql.cast_bittext_to_bytea(text);
DROP FUNCTION IF EXISTS mysql.cast_bit_to_bytea(bit);
CREATE OR REPLACE FUNCTION mysql.cast_bit_to_bytea(pg_catalog.bit)
RETURNS bytea
AS '$libdir/mysm', 'cast_bittext_to_bytea'
LANGUAGE C STRICT IMMUTABLE;
create cast (pg_catalog.bit as bytea) with function mysql.cast_bit_to_bytea as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_text_to_bigint_for_mysql(text)
RETURNS int8
AS '$libdir/mysm', 'convert_text_to_bigint_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

create or replace function mysql.cast_char_to_tinyint(char)
returns int2
as
$$
DECLARE
    tmp int2;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1::text));
        if (tmp is not null) then
            return tmp::int2;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (char as int2) with function mysql.cast_char_to_tinyint as ASSIGNMENT;

create or replace function mysql.cast_char_to_int(char)
returns int4
as
$$
DECLARE
    tmp int4;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1::text));
        if (tmp is not null) then
            return tmp::int4;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (char as int4) with function mysql.cast_char_to_int as ASSIGNMENT;

create or replace function mysql.cast_char_to_bigint(char)
returns int8
as
$$
DECLARE
    tmp int8;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1::text));
        if (tmp is not null) then
            return tmp;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (char as int8) with function mysql.cast_char_to_bigint as ASSIGNMENT;

create or replace function mysql.cast_varchar_to_tinyint(varchar)
returns int2
as
$$
DECLARE
    tmp int2;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1::text));
        if (tmp is not null) then
            return tmp::int2;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (varchar as int2) with function mysql.cast_varchar_to_tinyint as ASSIGNMENT;

create or replace function mysql.cast_varchar_to_int(varchar)
returns int4
as
$$
DECLARE
    tmp int4;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1::text));
        if (tmp is not null) then
            return tmp::int4;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (varchar as int4) with function mysql.cast_varchar_to_int as ASSIGNMENT;

create or replace function mysql.cast_varchar_to_bigint(varchar)
returns int8
as
$$
DECLARE
    tmp int8;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1::text));
        if (tmp is not null) then
            return tmp;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (varchar as int8) with function mysql.cast_varchar_to_bigint as ASSIGNMENT;

create or replace function mysql.cast_text_to_tinyint(text)
returns int2
as
$$
DECLARE
    tmp int2;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1));
        if (tmp is not null) then
            return tmp::int2;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (text as int2) with function mysql.cast_text_to_tinyint as ASSIGNMENT;

create or replace function mysql.cast_text_to_int(text)
returns int4
as
$$
DECLARE
    tmp int4;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1));
        if (tmp is not null) then
            return tmp::int4;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (text as int4) with function mysql.cast_text_to_int as ASSIGNMENT;

create or replace function mysql.cast_text_to_bigint(text)
returns int8
as
$$
DECLARE
    tmp int8;
begin
    if $1 is not null then
        tmp = (mysql.convert_text_to_bigint_for_mysql($1));
        if (tmp is not null) then
            return tmp;
        else
            raise exception 'Data truncated';
        end if;
    else
        return null;
    end if;
end;
$$
language 'plpgsql';
create cast (text as int8) with function mysql.cast_text_to_bigint as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_varbit_to_smallint(pg_catalog.varbit)
RETURNS pg_catalog.int2
AS '$libdir/mysm', 'convertVarbitToSmallint'
LANGUAGE C STRICT IMMUTABLE;

create or replace function mysql.cast_varbit_to_smallint(pg_catalog.varbit)
returns pg_catalog.int2
as
$$
declare
    tmp pg_catalog.int2;
begin
    tmp = mysql.convert_varbit_to_smallint($1);
    if tmp is not null then
        return tmp;
    else
        raise exception 'Out of range';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.varbit as pg_catalog.int2) with function mysql.cast_varbit_to_smallint as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_varbit_to_int(pg_catalog.varbit)
RETURNS pg_catalog.int4
AS '$libdir/mysm', 'convertVarbitToInt'
LANGUAGE C STRICT IMMUTABLE;

create or replace function mysql.cast_varbit_to_int(pg_catalog.varbit)
returns pg_catalog.int4
as
$$
declare
    tmp pg_catalog.int4;
begin
    tmp = mysql.convert_varbit_to_int($1);
    if tmp is not null then
        return tmp;
    else
        raise exception 'Out of range';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.varbit as pg_catalog.int4) with function mysql.cast_varbit_to_int as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_varbit_to_bigint(pg_catalog.varbit)
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'convertVarbitToBigint'
LANGUAGE C STRICT IMMUTABLE;

create or replace function mysql.cast_varbit_to_bigint(pg_catalog.varbit)
returns pg_catalog.int8
as
$$
declare
    tmp pg_catalog.int8;
begin
    tmp = mysql.convert_varbit_to_bigint($1);
    if tmp is not null then
        return tmp;
    else
        raise exception 'Out of range';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.varbit as pg_catalog.int8) with function mysql.cast_varbit_to_bigint as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_smallint_to_varbit(pg_catalog.int2)
RETURNS pg_catalog.varbit
AS '$libdir/mysm', 'convertSmallintToVarbit'
LANGUAGE C STRICT IMMUTABLE;

create or replace function mysql.cast_smallint_to_varbit(pg_catalog.int2)
returns pg_catalog.varbit
as
$$
begin
    return mysql.convert_smallint_to_varbit($1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.int2 as pg_catalog.varbit) with function mysql.cast_smallint_to_varbit as assignment;

CREATE OR REPLACE FUNCTION mysql.convert_int_to_varbit(pg_catalog.int4)
returns pg_catalog.varbit
AS '$libdir/mysm', 'convertIntToVarbit'
LANGUAGE C STRICT IMMUTABLE;

create or replace function mysql.cast_int_to_varbit(pg_catalog.int4)
returns pg_catalog.varbit
as
$$
begin
    return mysql.convert_int_to_varbit($1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.int4 as pg_catalog.varbit) with function mysql.cast_int_to_varbit as assignment;

CREATE OR REPLACE FUNCTION mysql.convert_bigint_to_varbit(pg_catalog.int8)
RETURNS pg_catalog.varbit
AS '$libdir/mysm', 'convertBigintToVarbit'
LANGUAGE C STRICT IMMUTABLE;

create or replace function mysql.cast_bigint_to_varbit(pg_catalog.int8)
returns pg_catalog.varbit
as
$$
begin
    return mysql.convert_bigint_to_varbit($1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.int8 as pg_catalog.varbit) with function mysql.cast_bigint_to_varbit as assignment;

create or replace function mysql.cast_bool_to_varbit(pg_catalog.bool)
returns pg_catalog.varbit
as
$$
begin
    if $1 then
        return b'1';
    else
        return b'0';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.bool as pg_catalog.varbit) with function mysql.cast_bool_to_varbit as assignment;

create or replace function mysql.bytea2int8(pg_catalog.bytea)
returns pg_catalog.int8
as '$libdir/mysm', 'mys_bytea2int8'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.int8) with function mysql.bytea2int8(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2int4(pg_catalog.bytea)
returns pg_catalog.int4
as '$libdir/mysm', 'mys_bytea2int4'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.int4) with function mysql.bytea2int4(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2int2(pg_catalog.bytea)
returns pg_catalog.int2
as '$libdir/mysm', 'mys_bytea2int2'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.int2) with function mysql.bytea2int2(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2numeric(pg_catalog.bytea)
returns pg_catalog.numeric
as '$libdir/mysm', 'mys_bytea2numeric'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.numeric) with function mysql.bytea2numeric(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2float8(pg_catalog.bytea)
returns pg_catalog.float8
as '$libdir/mysm', 'mys_bytea2float8'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.float8) with function mysql.bytea2float8(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2float4(pg_catalog.bytea)
returns pg_catalog.float4
as '$libdir/mysm', 'mys_bytea2float4'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.float4) with function mysql.bytea2float4(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2text(pg_catalog.bytea)
returns pg_catalog.text
as '$libdir/mysm', 'mys_bytea2text'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.text) with function mysql.bytea2text(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2varchar(pg_catalog.bytea)
returns pg_catalog.varchar
as '$libdir/mysm', 'mys_bytea2varchar'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.varchar) with function mysql.bytea2varchar(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2bpchar(pg_catalog.bytea)
returns pg_catalog.bpchar
as '$libdir/mysm', 'mys_bytea2bpchar'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.bpchar) with function mysql.bytea2bpchar(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2date(pg_catalog.bytea)
returns pg_catalog.date
as '$libdir/mysm', 'mys_bytea2date'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.date) with function mysql.bytea2date(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2time(pg_catalog.bytea)
returns pg_catalog.time
as '$libdir/mysm', 'mys_bytea2time'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.time) with function mysql.bytea2time(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2timetz(pg_catalog.bytea)
returns pg_catalog.timetz
as '$libdir/mysm', 'mys_bytea2timetz'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.timetz) with function mysql.bytea2timetz(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2timestamp(pg_catalog.bytea)
returns pg_catalog.timestamp
as '$libdir/mysm', 'mys_bytea2timestamp'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.timestamp) with function mysql.bytea2timestamp(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2timestamptz(pg_catalog.bytea)
returns pg_catalog.timestamptz
as '$libdir/mysm', 'mys_bytea2timestamptz'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.timestamptz) with function mysql.bytea2timestamptz(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2bool(pg_catalog.bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'mys_bytea2bool'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.bool) with function mysql.bytea2bool(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2bit(pg_catalog.bytea)
returns pg_catalog.bit
as '$libdir/mysm', 'mys_bytea2bit'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.bit) with function mysql.bytea2bit(pg_catalog.bytea) as assignment;

create or replace function mysql.bytea2varbit(pg_catalog.bytea)
returns pg_catalog.varbit
as '$libdir/mysm', 'mys_bytea2varbit'
LANGUAGE C STRICT IMMUTABLE;
create cast(pg_catalog.bytea as pg_catalog.varbit) with function mysql.bytea2varbit(pg_catalog.bytea) as assignment;

create or replace function mysql.cast_smallint_to_boolean(int2)
returns pg_catalog.bool
as
$$
begin
    if $1 != 0 then
        return true;
    else
        return false;
    end if;
end;
$$
language 'plpgsql' strict;
create cast (int2 as pg_catalog.bool) with function mysql.cast_smallint_to_boolean as implicit;

create or replace function mysql.cast_bigint_to_boolean(int8)
returns pg_catalog.bool
as
$$
begin
    if $1 != 0 then
        return true;
    else
        return false;
    end if;
end;
$$
language 'plpgsql' strict;
create cast (int8 as pg_catalog.bool) with function mysql.cast_bigint_to_boolean as implicit;

create or replace function mysql.cast_bit_to_boolean(pg_catalog.bit)
returns pg_catalog.bool
as
$$
begin
    if pg_catalog.int8($1) != 0 then
        return true;
    else
        return false;
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.bit as pg_catalog.bool) with function mysql.cast_bit_to_boolean as implicit;

create or replace function mysql.cast_varbit_to_boolean(pg_catalog.varbit)
returns pg_catalog.bool
as
$$
begin
    if pg_catalog.int8($1) != 0 then
        return true;
    else
        return false;
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.varbit as pg_catalog.bool) with function mysql.cast_varbit_to_boolean as implicit;

DROP FUNCTION IF EXISTS mysql.convert_varbit_to_smallint(pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_varbit_to_smallint(pg_catalog.varbit)
RETURNS pg_catalog.int2
AS '$libdir/mysm', 'convertVarbitToSmallint'
LANGUAGE C STRICT IMMUTABLE;

drop function if exists mysql.cast_varbit_to_smallint(pg_catalog.varbit) cascade;
create or replace function mysql.cast_varbit_to_smallint(pg_catalog.varbit)
returns pg_catalog.int2
as
$$
declare
tmp pg_catalog.int2;
begin
    tmp = mysql.convert_varbit_to_smallint($1);
    if tmp is not null then
        return tmp;
    else
        raise exception 'Out of range';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.varbit as pg_catalog.int2) with function mysql.cast_varbit_to_smallint as ASSIGNMENT;

DROP FUNCTION IF EXISTS mysql.convert_varbit_to_int(pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_varbit_to_int(pg_catalog.varbit)
RETURNS pg_catalog.int4
AS '$libdir/mysm', 'convertVarbitToInt'
LANGUAGE C STRICT IMMUTABLE;

drop function if exists mysql.cast_varbit_to_int(pg_catalog.varbit) cascade;
create or replace function mysql.cast_varbit_to_int(pg_catalog.varbit)
returns pg_catalog.int4
as
$$
declare
tmp pg_catalog.int4;
begin
    tmp = mysql.convert_varbit_to_int($1);
    if tmp is not null then
        return tmp;
    else
        raise exception 'Out of range';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.varbit as pg_catalog.int4) with function mysql.cast_varbit_to_int as ASSIGNMENT;

DROP FUNCTION IF EXISTS mysql.convert_varbit_to_bigint(pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_varbit_to_bigint(pg_catalog.varbit)
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'convertVarbitToBigint'
LANGUAGE C STRICT IMMUTABLE;

DROP function if exists mysql.cast_varbit_to_bigint(pg_catalog.varbit) cascade;
create or replace function mysql.cast_varbit_to_bigint(pg_catalog.varbit)
returns pg_catalog.int8
as
$$
declare
tmp pg_catalog.int8;
begin
    tmp = mysql.convert_varbit_to_bigint($1);
    if tmp is not null then
        return tmp;
    else
        raise exception 'Out of range';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.varbit as pg_catalog.int8) with function mysql.cast_varbit_to_bigint as ASSIGNMENT;

DROP FUNCTION IF EXISTS mysql.convert_smallint_to_varbit(pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_smallint_to_varbit(pg_catalog.int2)
RETURNS pg_catalog.varbit
AS '$libdir/mysm', 'convertSmallintToVarbit'
LANGUAGE C STRICT IMMUTABLE;

drop function if exists mysql.cast_smallint_to_varbit(pg_catalog.int2) cascade;
create or replace function mysql.cast_smallint_to_varbit(pg_catalog.int2)
returns pg_catalog.varbit
as
$$
begin
    return mysql.convert_smallint_to_varbit($1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.int2 as pg_catalog.varbit) with function mysql.cast_smallint_to_varbit as assignment;

DROP FUNCTION IF EXISTS mysql.convert_int_to_varbit(pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_int_to_varbit(pg_catalog.int4)
returns pg_catalog.varbit
AS '$libdir/mysm', 'convertIntToVarbit'
LANGUAGE C STRICT IMMUTABLE;

drop function if exists mysql.cast_int_to_varbit(pg_catalog.int4) cascade;
create or replace function mysql.cast_int_to_varbit(pg_catalog.int4)
returns pg_catalog.varbit
as
$$
begin
    return mysql.convert_int_to_varbit($1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.int4 as pg_catalog.varbit) with function mysql.cast_int_to_varbit as assignment;

DROP FUNCTION IF EXISTS mysql.convert_bigint_to_varbit(pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_bigint_to_varbit(pg_catalog.int8)
RETURNS pg_catalog.varbit
AS '$libdir/mysm', 'convertBigintToVarbit'
LANGUAGE C STRICT IMMUTABLE;

drop function if exists mysql.cast_bigint_to_varbit(pg_catalog.int8) cascade;
create or replace function mysql.cast_bigint_to_varbit(pg_catalog.int8)
returns pg_catalog.varbit
as
$$
begin
    return mysql.convert_bigint_to_varbit($1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.int8 as pg_catalog.varbit) with function mysql.cast_bigint_to_varbit as assignment;

drop function if exists mysql.cast_bool_to_varbit(pg_catalog.bool) cascade;
create or replace function mysql.cast_bool_to_varbit(pg_catalog.bool)
returns pg_catalog.varbit
as
$$
begin
    if $1 then
        return b'1';
    else
        return b'0';
    end if;
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.bool as pg_catalog.varbit) with function mysql.cast_bool_to_varbit as assignment;

drop function if exists mysql.cast_text_to_time(pg_catalog.text) cascade;
create or replace function mysql.cast_text_to_time(pg_catalog.text)
returns pg_catalog.time
as
$$
begin
    return pg_catalog.time_in($1::cstring, 0::Oid, -1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.text as pg_catalog.time) with function mysql.cast_text_to_time as ASSIGNMENT;

drop function if exists mysql.cast_text_to_date(pg_catalog.text) cascade;
create or replace function mysql.cast_text_to_date(pg_catalog.text)
returns pg_catalog.date
as
$$
begin
    return pg_catalog.date_in($1::cstring);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.text as pg_catalog.date) with function mysql.cast_text_to_date as ASSIGNMENT;

drop function if exists mysql.cast_text_to_timestamp(pg_catalog.text) cascade;
create or replace function mysql.cast_text_to_timestamp(pg_catalog.text)
returns pg_catalog.timestamp
as
$$
begin
    return pg_catalog.timestamp_in($1::cstring, 0::Oid, -1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.text as pg_catalog.timestamp) with function mysql.cast_text_to_timestamp as ASSIGNMENT;

drop function if exists mysql.cast_text_to_timestamptz(pg_catalog.text) cascade;
create or replace function mysql.cast_text_to_timestamptz(pg_catalog.text)
returns pg_catalog.timestamptz
as
$$
begin
    return pg_catalog.timestamptz_in($1::cstring, 0::Oid, -1);
end;
$$
language 'plpgsql' strict;
create cast (pg_catalog.text as pg_catalog.timestamptz) with function mysql.cast_text_to_timestamptz as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_text_to_float8(pg_catalog.text)
RETURNS pg_catalog.float8
AS '$libdir/mysm', 'mys_convertTextToFloat8'
LANGUAGE C STRICT IMMUTABLE;
create cast (pg_catalog.text as pg_catalog.float8) with function mysql.convert_text_to_float8 as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_varchar_to_float8(pg_catalog.varchar)
RETURNS pg_catalog.float8
AS
$$
BEGIN
    return mysql.convert_text_to_float8($1::text);
END;
$$
LANGUAGE plpgsql;
create cast (pg_catalog.varchar as pg_catalog.float8) with function mysql.convert_varchar_to_float8 as ASSIGNMENT;

CREATE OR REPLACE FUNCTION mysql.convert_char_to_float8(pg_catalog.char)
RETURNS pg_catalog.float8
AS
$$
BEGIN
    return mysql.convert_text_to_float8($1::text);
END;
$$
LANGUAGE plpgsql;
create cast (pg_catalog.char as pg_catalog.float8) with function mysql.convert_char_to_float8 as ASSIGNMENT;


CREATE TYPE mysql.enum_proc AS ENUM('FUNCTION', 'PROCEDURE');
CREATE TYPE mysql.enum_security AS ENUM('INVOKER', 'DEFINER');


-- 如果OS上的icu是50.*版，则需要使用下面这个方式
-- 如果OS上的icu是60.*版及以上，则使用下面两个方式都可以
CREATE COLLATION mysql.case_insensitive (provider = icu, locale = '@colStrength=secondary', deterministic = false);
CREATE COLLATION mysql.ignore_accents (provider = icu, locale = 'und-u-ks-level1-kc-true', deterministic = false);


GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mysql TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mys_informa_schema TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA sys TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mys_sys TO public;


CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 mysql.smallint, arg2 mysql.smallint)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 int, arg2 int)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 bigint, arg2 bigint)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 char, arg2 char)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 varchar, arg2 varchar)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 text, arg2 text)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 name, arg2 name)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 time, arg2 time)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 timestamp, arg2 timestamp)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_and_eq(arg1 date, arg2 date)
returns pg_catalog.bool
AS
$$
BEGIN
    if arg1 is null then
        if arg2 is null then
            return true;
        else
            return false;
        end if;
    else
        if arg2 is null then
            return false;
        else
            if arg1 = arg2 then
                return true;
            else
                return false;
            end if;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = mysql.smallint,
    RIGHTARG = mysql.smallint
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = int,
    RIGHTARG = int
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = bigint,
    RIGHTARG = bigint
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = char,
    RIGHTARG = char
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = varchar,
    RIGHTARG = varchar
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = text,
    RIGHTARG = text
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = name,
    RIGHTARG = name
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = time,
    RIGHTARG = time
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = timestamp,
    RIGHTARG = timestamp
);

CREATE OPERATOR mysql.<=> (
    FUNCTION = mysql.is_and_eq,
    LEFTARG = date,
    RIGHTARG = date
);

CREATE OR REPLACE FUNCTION mysql.bpcharlike(character, text)
returns pg_catalog.bool
AS '$libdir/mysm', 'bpcharlike'
LANGUAGE C STRICT IMMUTABLE;
CREATE OPERATOR mysql.~~ (
    FUNCTION = mysql.bpcharlike,
    LEFTARG = character,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bpcharnlike(character, text)
returns pg_catalog.bool
AS '$libdir/mysm', 'bpcharnlike'
LANGUAGE C STRICT IMMUTABLE;
CREATE OPERATOR mysql.!~~ (
    FUNCTION = mysql.bpcharnlike,
    LEFTARG = character,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.int2EqBool(mysql.smallint, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return true;
    elsif ($1 = 0) and ($2 = false) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int2EqBool,
    LEFTARG = mysql.smallint,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolEqInt2(pg_catalog.bool, mysql.smallint)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return true;
    elsif ($1 = false) and ($2 = 0) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.boolEqInt2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.int2NeBool(mysql.smallint, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return false;
    elsif ($1 = 0) and ($2 = false) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.int2NeBool,
    LEFTARG = mysql.smallint,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolNeInt2(pg_catalog.bool, mysql.smallint)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return false;
    elsif ($1 = false) and ($2 = 0) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.boolNeInt2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.int4EqBool(int, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return true;
    elsif ($1 = 0) and ($2 = false) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int4EqBool,
    LEFTARG = int,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolEqInt4(pg_catalog.bool, int)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return true;
    elsif ($1 = false) and ($2 = 0) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.boolEqInt4,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = int
);

CREATE OR REPLACE FUNCTION mysql.int4NeBool(int, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return false;
    elsif ($1 = 0) and ($2 = false) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.int4NeBool,
    LEFTARG = int,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolNeInt4(pg_catalog.bool, int)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return false;
    elsif ($1 = false) and ($2 = 0) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.boolNeInt4,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = int
);

CREATE OR REPLACE FUNCTION mysql.int8EqBool(bigint, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return true;
    elsif ($1 = 0) and ($2 = false) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int8EqBool,
    LEFTARG = bigint,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolEqInt8(pg_catalog.bool, bigint)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return true;
    elsif ($1 = false) and ($2 = 0) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.boolEqInt8,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.int8NeBool(bigint, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return false;
    elsif ($1 = 0) and ($2 = false) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.int8NeBool,
    LEFTARG = bigint,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolNeInt8(pg_catalog.bool, bigint)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return false;
    elsif ($1 = false) and ($2 = 0) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.boolNeInt8,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.convert_digit_text_to_text_for_mysql(text)
RETURNS text
AS '$libdir/mysm', 'convert_digit_text_to_text_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.convert_text_to_digit_text_for_mysql(text)
RETURNS text
AS '$libdir/mysm', 'convert_text_to_digit_text_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.smallintbgtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(mysql.smallint, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.smallintbgtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerbgtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(integer, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.integerbgtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintbgtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(bigint, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.bigintbgtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, mysql.smallint);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textbginteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, integer);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbginteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textbgbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, bigint);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);


CREATE OR REPLACE FUNCTION mysql.smallintbgeqtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(mysql.smallint, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.smallintbgeqtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerbgeqtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(integer, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.integerbgeqtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintbgeqtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(bigint, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.bigintbgeqtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgeqsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, mysql.smallint);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textbgeqinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, integer);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textbgeqbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, bigint);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.smallintletext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(mysql.smallint, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.smallintletext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerletext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(integer, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.integerletext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintletext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(bigint, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.bigintletext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textlesmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, mysql.smallint);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlesmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textleinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, integer);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textleinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textlebigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, bigint);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlebigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.smallintleeqtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(mysql.smallint, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.smallintleeqtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerleeqtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(integer, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.integerleeqtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintleeqtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(bigint, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.bigintleeqtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textleeqsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, mysql.smallint);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textleeqinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, integer);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textleeqbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, bigint);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.convert_digit_text_to_text_for_mysql(text)
RETURNS text
AS '$libdir/mysm', 'convert_digit_text_to_text_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.convert_text_to_digit_text_for_mysql(text)
RETURNS text
AS '$libdir/mysm', 'convert_text_to_digit_text_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.smallintbgtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';

drop operator if exists mysql.>(mysql.smallint, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.smallintbgtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerbgtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
drop operator if exists mysql.>(integer, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.integerbgtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintbgtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
drop operator if exists mysql.>(bigint, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.bigintbgtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
drop operator if exists mysql.>(text, mysql.smallint);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textbginteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
drop operator if exists mysql.>(text, integer);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbginteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textbgbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
drop operator if exists mysql.>(text, bigint);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.smallintbgeqtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(mysql.smallint, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.smallintbgeqtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerbgeqtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(integer, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.integerbgeqtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintbgeqtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(bigint, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.bigintbgeqtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgeqsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, mysql.smallint);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textbgeqinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, integer);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textbgeqbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, bigint);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.smallintletext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(mysql.smallint, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.smallintletext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerletext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(integer, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.integerletext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintletext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(bigint, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.bigintletext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textlesmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, mysql.smallint);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlesmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textleinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, integer);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textleinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textlebigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, bigint);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlebigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.smallintleeqtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(mysql.smallint, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.smallintleeqtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.integerleeqtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(integer, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.integerleeqtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigintleeqtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(bigint, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.bigintleeqtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textleeqsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, mysql.smallint);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.textleeqinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, integer);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.textleeqbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, bigint);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.numericeqtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 = tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.numericeqtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.timeeqtext(time, text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 = str_to_date($2, '%H:%i:%s');
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.timeeqtext,
    LEFTARG = time,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.dateeqtext(date, text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 = str_to_date($2, '%Y-%m-%d');
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.dateeqtext,
    LEFTARG = date,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.timestampeqtext(timestamp, text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 = str_to_date($2, '%Y-%m-%d %H:%i:%s');
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.timestampeqtext,
    LEFTARG = timestamp,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.texteqtime(text, time)
returns pg_catalog.bool
AS
$$
BEGIN
    return str_to_date($1, '%H:%i:%s') = $2;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.texteqtime,
    LEFTARG = text,
    RIGHTARG = time
);

CREATE OR REPLACE FUNCTION mysql.texteqdate(text, date)
returns pg_catalog.bool
AS
$$
BEGIN
    return (str_to_date($1, '%Y-%m-%d')) = $2;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.texteqdate,
    LEFTARG = text,
    RIGHTARG = date
);

CREATE OR REPLACE FUNCTION mysql.texteqtimestamp(text, timestamp)
returns pg_catalog.bool
AS
$$
BEGIN
    return str_to_date($1, '%Y-%m-%d %H:%i:%s') = $2;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.texteqtimestamp,
    LEFTARG = text,
    RIGHTARG = timestamp
);

CREATE OR REPLACE FUNCTION mysql.textne(text, text)
returns pg_catalog.bool
AS '$libdir/mysm', 'textne_mys'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.numericnetext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 != tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.numericnetext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.timenetext(time, text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 != str_to_date($2, '%H:%i:%s');
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.timenetext,
    LEFTARG = time,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.datenetext(date, text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 != str_to_date($2, '%Y-%m-%d');
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.datenetext,
    LEFTARG = date,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.timestampnetext(timestamp, text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 != str_to_date($2, '%Y-%m-%d %H:%i:%s');
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.timestampnetext,
    LEFTARG = timestamp,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textnenumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 != tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.textnenumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textlenumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, numeric);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlenumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textleeqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, numeric);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textbgnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
drop operator if exists mysql.>(text, numeric);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textbgeqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, numeric);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.numericletext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(numeric, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.numericletext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericleeqtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(numeric, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.numericleeqtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericbgtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
drop operator if exists mysql.>(numeric, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.numericbgtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericbgeqtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(numeric, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.numericbgeqtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textnetime(text, time)
returns pg_catalog.bool
AS
$$
BEGIN
    return str_to_date($1, '%H:%i:%s') != $2;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.textnetime,
    LEFTARG = text,
    RIGHTARG = time
);

CREATE OR REPLACE FUNCTION mysql.textnedate(text, date)
returns pg_catalog.bool
AS
$$
BEGIN
    return str_to_date($1, '%Y-%m-%d') != $2;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.textnedate,
    LEFTARG = text,
    RIGHTARG = date
);

CREATE OR REPLACE FUNCTION mysql.textnetimestamp(text, timestamp)
returns pg_catalog.bool
AS
$$
BEGIN
    return str_to_date($1, '%Y-%m-%d %H:%i:%s') != $2;
END
$$
language 'plpgsql';
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.textnetimestamp,
    LEFTARG = text,
    RIGHTARG = timestamp
);

CREATE OR REPLACE FUNCTION mysql.char_eq_char_for_date_format(character, character)
returns pg_catalog.bool
AS '$libdir/mysm', 'char_eq_char_for_date_format'
LANGUAGE C STRICT IMMUTABLE;
CREATE OPERATOR mysql.=# (
    FUNCTION = mysql.char_eq_char_for_date_format,
    LEFTARG = character,
    RIGHTARG = character
);

CREATE OR REPLACE FUNCTION mysql.text_pl_interval(text, pg_catalog.interval)
RETURNS timestamp without time zone
LANGUAGE plpgsql
AS $function$
begin
    return $1::timestamp(6) + $2;
end;
$function$;
DROP OPERATOR IF EXISTS mysql.+(text, pg_catalog.interval);
CREATE OPERATOR mysql.+(
    function = mysql.text_pl_interval,
    leftarg = text,
    rightarg = pg_catalog.interval
);

CREATE OR REPLACE FUNCTION mysql.interval_pl_text(pg_catalog.interval, text)
RETURNS timestamp without time zone
LANGUAGE plpgsql
AS $function$
begin
    return $1 + $2::timestamp(6);
end;
$function$;
DROP OPERATOR IF EXISTS mysql.+(pg_catalog.interval, pg_catalog.text);
CREATE OPERATOR mysql.+(
    function = mysql.interval_pl_text,
    leftarg = pg_catalog.interval,
    rightarg = text
);

CREATE OR REPLACE FUNCTION mysql.text_mi_interval(text, pg_catalog.interval)
RETURNS timestamp without time zone
LANGUAGE plpgsql
AS $function$
begin
    return $1::timestamp(6) - $2;
end;
$function$;
DROP OPERATOR IF EXISTS mysql.-(pg_catalog.text, pg_catalog.interval);
CREATE OPERATOR mysql.-(
    function = mysql.text_mi_interval,
    leftarg = text,
    rightarg = pg_catalog.interval
);

CREATE OR REPLACE FUNCTION mysql.texteqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 = tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(text, numeric);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.texteqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textlenumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, numeric);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlenumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textleeqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, numeric);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textbgnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, numeric);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textbgeqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1);
        tmp2 = mysql.convert_digit_text_to_text_for_mysql($2::text);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, numeric);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.numericletext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(numeric, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.numericletext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericleeqtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(numeric, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.numericleeqtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericbgtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(numeric, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.numericbgtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericbgeqtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 text;
    tmp2 text;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_digit_text_to_text_for_mysql($1::text);
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2);
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(numeric, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.numericbgeqtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

-- 为了date_format自定义函数中，比较时一定会区分大小写
CREATE OR REPLACE FUNCTION mysql.char_eq_char_for_date_format(character, character)
returns pg_catalog.bool
AS '$libdir/mysm', 'char_eq_char_for_date_format'
LANGUAGE C STRICT IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.=#(character, character);
CREATE OPERATOR mysql.=# (
    FUNCTION = mysql.char_eq_char_for_date_format,
    LEFTARG = character,
    RIGHTARG = character
);

CREATE OR REPLACE FUNCTION mysql.text_add_text(text, text)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;

    if ((tmp1 = null) or (tmp2 = null)) then
        return null;
    end if;

    return tmp1 + tmp2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(pg_catalog.text, pg_catalog.text);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.text_add_text,
    LEFTARG = text,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.char_add_char(char, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_add_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(char, char);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.char_add_char,
    LEFTARG = char,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.varchar_add_varchar(varchar, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_add_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(varchar, varchar);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.varchar_add_varchar,
    LEFTARG = varchar,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.text_add_bigint(text, bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 + $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(text, bigint);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.text_add_bigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.char_add_bigint(char, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_add_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(char, bigint);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.char_add_bigint,
    LEFTARG = char,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.varchar_add_bigint(varchar, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_add_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(varchar, bigint);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.varchar_add_bigint,
    LEFTARG = varchar,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigint_add_text(bigint, text)
RETURNS bigint
AS
$$
DECLARE
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
    if (tmp2 = null) then
        return null;
    end if;

    return $1 + tmp2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(bigint, text);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.bigint_add_text,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigint_add_varchar(bigint, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_add_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(bigint, varchar);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.bigint_add_varchar,
    LEFTARG = bigint,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.bigint_add_char(bigint, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_add_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(bigint, char);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.bigint_add_char,
    LEFTARG = bigint,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.text_minus_text(text, text)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;

    if ((tmp1 = null) or (tmp2 = null)) then
        return null;
    end if;

    return tmp1 - tmp2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(text, text);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.text_minus_text,
    LEFTARG = text,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.char_minus_char(char, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_minus_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(char, char);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.char_minus_char,
    LEFTARG = char,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.varchar_minus_varchar(varchar, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_minus_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(varchar, varchar);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.varchar_minus_varchar,
    LEFTARG = varchar,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.text_minus_bigint(text, bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 - $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(text, bigint);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.text_minus_bigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.char_minus_bigint(char, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_minus_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(char, bigint);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.char_minus_bigint,
    LEFTARG = char,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.varchar_minus_bigint(varchar, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_minus_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(varchar, bigint);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.varchar_minus_bigint,
    LEFTARG = varchar,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigint_minus_text(bigint, text)
RETURNS bigint
AS
$$
DECLARE
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
    if (tmp2 = null) then
        return null;
    end if;

    return $1 - tmp2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(bigint, text);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.bigint_minus_text,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigint_minus_varchar(bigint, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_minus_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(bigint, varchar);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.bigint_minus_varchar,
    LEFTARG = bigint,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.bigint_minus_char(bigint, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_minus_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(bigint, char);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.bigint_minus_char,
    LEFTARG = bigint,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.text_multi_text(text, text)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;

    if ((tmp1 = null) or (tmp2 = null)) then
        return null;
    end if;

    return tmp1 * tmp2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.text_multi_text,
    LEFTARG = text,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.char_multi_char(char, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_multi_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.char_multi_char,
    LEFTARG = char,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.varchar_multi_varchar(varchar, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_multi_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.varchar_multi_varchar,
    LEFTARG = varchar,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.text_multi_bigint(text, bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 * $2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.text_multi_bigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.char_multi_bigint(char, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_multi_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.char_multi_bigint,
    LEFTARG = char,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.varchar_multi_bigint(varchar, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_multi_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.varchar_multi_bigint,
    LEFTARG = varchar,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigint_multi_text(bigint, text)
RETURNS bigint
AS
$$
DECLARE
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
    if (tmp2 = null) then
        return null;
    end if;

    return $1 * tmp2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.bigint_multi_text,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigint_multi_varchar(bigint, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_multi_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.bigint_multi_varchar,
    LEFTARG = bigint,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.bigint_multi_char(bigint, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_multi_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.* (
    FUNCTION = mysql.bigint_multi_char,
    LEFTARG = bigint,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.text_divide_text(text, text)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;

    if ((tmp1 = null) or (tmp2 = null) or (tmp2 = 0)) then
        return null;
    end if;

    return tmp1 / tmp2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.text_divide_text,
    LEFTARG = text,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.char_divide_char(char, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_divide_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.char_divide_char,
    LEFTARG = char,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.varchar_divide_varchar(varchar, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_divide_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.varchar_divide_varchar,
    LEFTARG = varchar,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.text_divide_bigint(text, bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
BEGIN
    if (($1 = null) or ($2 = null) or ($2 = 0)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 / $2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.text_divide_bigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.char_divide_bigint(char, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_divide_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.char_divide_bigint,
    LEFTARG = char,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.varchar_divide_bigint(varchar, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_divide_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.varchar_divide_bigint,
    LEFTARG = varchar,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigint_divide_text(bigint, text)
RETURNS bigint
AS
$$
DECLARE
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
    if ((tmp2 = null) or (tmp2 = 0)) then
        return null;
    end if;

    return $1 / tmp2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.bigint_divide_text,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigint_divide_varchar(bigint, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_divide_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.bigint_divide_varchar,
    LEFTARG = bigint,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.bigint_divide_char(bigint, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_divide_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql./ (
    FUNCTION = mysql.bigint_divide_char,
    LEFTARG = bigint,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.text_mod_text(text, text)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;

    if ((tmp1 = null) or (tmp2 = null) or (tmp2 = 0)) then
        return null;
    end if;

    return tmp1 % tmp2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.text_mod_text,
    LEFTARG = text,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.char_mod_char(char, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_mod_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.char_mod_char,
    LEFTARG = char,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.varchar_mod_varchar(varchar, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_mod_text($1::text, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.varchar_mod_varchar,
    LEFTARG = varchar,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.text_mod_bigint(text, bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
BEGIN
    if (($1 = null) or ($2 = null) or ($2 = 0)) then
        return null;
    end if;

    tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 % $2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.text_mod_bigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.char_mod_bigint(char, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_mod_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.char_mod_bigint,
    LEFTARG = char,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.varchar_mod_bigint(varchar, bigint)
RETURNS bigint
AS
$$
BEGIN
    return mysql.text_mod_bigint($1::text, $2);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.varchar_mod_bigint,
    LEFTARG = varchar,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigint_mod_text(bigint, text)
RETURNS bigint
AS
$$
DECLARE
    tmp2 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
    if ((tmp2 = null) or (tmp2 = 0)) then
        return null;
    end if;

    return $1 % tmp2;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.bigint_mod_text,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.bigint_mod_varchar(bigint, varchar)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_mod_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.bigint_mod_varchar,
    LEFTARG = bigint,
    RIGHTARG = varchar
);

CREATE OR REPLACE FUNCTION mysql.bigint_mod_char(bigint, char)
RETURNS bigint
AS
$$
BEGIN
    return mysql.bigint_mod_text($1, $2::text);
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.% (
    FUNCTION = mysql.bigint_mod_char,
    LEFTARG = bigint,
    RIGHTARG = char
);

CREATE OR REPLACE FUNCTION mysql.convert_time_text_to_numeric_for_mysql(text)
RETURNS float8
AS '$libdir/mysm', 'convert_time_text_to_numeric_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.time_add_bigint(time, bigint)
RETURNS float8
AS
$$
DECLARE
    tmp1 float8;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text);

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 + $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(time, bigit);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.time_add_bigint,
    LEFTARG = time,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.date_add_smallint(pg_catalog.date, pg_catalog.int2)
RETURNS int
AS
$$
BEGIN
    return mysql.date_add_int($1, $2);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(pg_catalog.date, pg_catalog.int2);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.date_add_smallint,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.date_add_int(date, int)
RETURNS int
AS
$$
DECLARE
    tmp1 int;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text)::int;

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 + $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(date, int);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.date_add_int,
    LEFTARG = date,
    RIGHTARG = int
);

CREATE OR REPLACE FUNCTION mysql.date_add_bigint(date, bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text)::bigint;

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 + $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(date, bigint);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.date_add_bigint,
    LEFTARG = date,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.timestamp_add_bigint(timestamp, bigint)
RETURNS float8
AS
$$
DECLARE
    tmp1 float8;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text);

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 + $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.+(timestamp, bigint);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql.timestamp_add_bigint,
    LEFTARG = timestamp,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.time_minus_bigint(time, bigint)
RETURNS float8
AS
$$
DECLARE
    tmp1 float8;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text);

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 - $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(time, bigint);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.time_minus_bigint,
    LEFTARG = time,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.date_minus_smallint(pg_catalog.date, pg_catalog.int2)
RETURNS pg_catalog.int4
AS
$$
BEGIN
    return mysql.date_minus_int($1, $2);
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(pg_catalog.date, pg_catalog.int2);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.date_minus_smallint,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.date_minus_int(date, int)
RETURNS int
AS
$$
DECLARE
    tmp1 int;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text)::int;

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 - $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(date, int);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.date_minus_int,
    LEFTARG = date,
    RIGHTARG = int
);

CREATE OR REPLACE FUNCTION mysql.date_minus_bigint(date, bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp1 bigint;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text)::bigint;

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 - $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(date, bigint);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.date_minus_bigint,
    LEFTARG = date,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.timestamp_minus_bigint(timestamp, bigint)
RETURNS float8
AS
$$
DECLARE
    tmp1 float8;
BEGIN
    if (($1 = null) or ($2 = null)) then
        return null;
    end if;

    tmp1 = mysql.convert_time_text_to_numeric_for_mysql($1::text);

    if (tmp1 = null) then
        return null;
    end if;

    return tmp1 - $2;
END;
$$
LANGUAGE plpgsql;
DROP OPERATOR IF EXISTS mysql.-(timestamp, bigint);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql.timestamp_minus_bigint,
    LEFTARG = timestamp,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.text_pl_interval(text, pg_catalog.interval)
RETURNS timestamp without time zone
LANGUAGE plpgsql
AS $function$
begin
    return $1::timestamp(6) + $2;
end;
$function$;
DROP OPERATOR IF EXISTS mysql.+(text, pg_catalog.interval);
CREATE OPERATOR mysql.+(
    function = mysql.text_pl_interval,
    leftarg = text,
    rightarg = pg_catalog.interval
);

CREATE OR REPLACE FUNCTION mysql.interval_pl_text(pg_catalog.interval, text)
RETURNS timestamp without time zone
LANGUAGE plpgsql
AS $function$
begin
    return $1 + $2::timestamp(6);
end;
$function$;
DROP OPERATOR IF EXISTS mysql.+(pg_catalog.interval, text);
CREATE OPERATOR mysql.+(
    function = mysql.interval_pl_text,
    leftarg = pg_catalog.interval,
    rightarg = text
);

CREATE OR REPLACE FUNCTION mysql.text_mi_interval(text, pg_catalog.interval)
RETURNS timestamp without time zone
LANGUAGE plpgsql
AS $function$
begin
    return $1::timestamp(6) - $2;
end;
$function$;
DROP OPERATOR IF EXISTS mysql.-(text, pg_catalog.interval);
CREATE OPERATOR mysql.-(
    function = mysql.text_mi_interval,
    leftarg = text,
    rightarg = pg_catalog.interval
);

CREATE OR REPLACE FUNCTION mysql.json_object_field(from_json json, field_name text)
RETURNS json
LANGUAGE sql
IMMUTABLE PARALLEL SAFE STRICT
AS $function$
    select pg_catalog.json_object_field($1, ltrim($2, '$.'));
$function$;
DROP OPERATOR IF EXISTS mysql.->(json, text);
CREATE OPERATOR mysql.-> (
    FUNCTION = mysql.json_object_field,
    LEFTARG = json,
    RIGHTARG = text
);

-- operators for text and numeric
CREATE OR REPLACE FUNCTION mysql.texteqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::numeric;
        tmp2 = $2;
        if tmp1 = tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(text, numeric);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.texteqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textlenumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::numeric;
        tmp2 = $2;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, numeric);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlenumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textleeqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::numeric;
        tmp2 = $2;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, numeric);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textbgnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::numeric;
        tmp2 = $2;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, numeric);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.textbgeqnumeric(text, numeric)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::numeric;
        tmp2 = $2;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, numeric);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqnumeric,
    LEFTARG = text,
    RIGHTARG = numeric
);

CREATE OR REPLACE FUNCTION mysql.numericletext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::numeric;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(numeric, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.numericletext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericleeqtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::numeric;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(numeric, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.numericleeqtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericbgtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::numeric;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(numeric, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.numericbgtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.numericbgeqtext(numeric, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::numeric;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(numeric, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.numericbgeqtext,
    LEFTARG = numeric,
    RIGHTARG = text
);

-- operators for text and smallint
CREATE OR REPLACE FUNCTION mysql.smallintbgtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::mysql.smallint;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(mysql.smallint, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.smallintbgtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::mysql.smallint;
        tmp2 = $2;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, mysql.smallint);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.smallintbgeqtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::mysql.smallint;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(mysql.smallint, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.smallintbgeqtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgeqsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::mysql.smallint;
        tmp2 = $2;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, mysql.smallint);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.smallintletext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::mysql.smallint;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(mysql.smallint, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.smallintletext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textlesmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::mysql.smallint;
        tmp2 = $2;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, mysql.smallint);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlesmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

CREATE OR REPLACE FUNCTION mysql.smallintleeqtext(mysql.smallint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::mysql.smallint;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(mysql.smallint, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.smallintleeqtext,
    LEFTARG = mysql.smallint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textleeqsmallint(text, mysql.smallint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 mysql.smallint;
    tmp2 mysql.smallint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::mysql.smallint;
        tmp2 = $2;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, mysql.smallint);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqsmallint,
    LEFTARG = text,
    RIGHTARG = mysql.smallint
);

-- operators for text and integer
CREATE OR REPLACE FUNCTION mysql.integerbgtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::integer;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(integer, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.integerbgtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbginteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::integer;
        tmp2 = $2;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, integer);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbginteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.integerbgeqtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::integer;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(integer, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.integerbgeqtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgeqinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::integer;
        tmp2 = $2;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, integer);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.integerletext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::integer;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(integer, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.integerletext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textleinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::integer;
        tmp2 = $2;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, integer);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textleinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

CREATE OR REPLACE FUNCTION mysql.integerleeqtext(integer, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::integer;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(integer, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.integerleeqtext,
    LEFTARG = integer,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textleeqinteger(text, integer)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 integer;
    tmp2 integer;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::integer;
        tmp2 = $2;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, integer);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqinteger,
    LEFTARG = text,
    RIGHTARG = integer
);

-- operators for text and bigint
CREATE OR REPLACE FUNCTION mysql.bigintbgtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(bigint, text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.bigintbgtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
        tmp2 = $2;
        if tmp1 > tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(text, bigint);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.textbgbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigintbgeqtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(bigint, text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.bigintbgeqtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textbgeqbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
        tmp2 = $2;
        if tmp1 >= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(text, bigint);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.textbgeqbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigintletext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(bigint, text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.bigintletext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textlebigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
        tmp2 = $2;
        if tmp1 < tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(text, bigint);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.textlebigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

CREATE OR REPLACE FUNCTION mysql.bigintleeqtext(bigint, text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = $1;
        tmp2 = mysql.convert_text_to_digit_text_for_mysql($2)::bigint;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(bigint, text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.bigintleeqtext,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.textleeqbigint(text, bigint)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 bigint;
    tmp2 bigint;
BEGIN
    if $1 is not null and $2 is not null then
        tmp1 = mysql.convert_text_to_digit_text_for_mysql($1)::bigint;
        tmp2 = $2;
        if tmp1 <= tmp2 then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(text, bigint);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.textleeqbigint,
    LEFTARG = text,
    RIGHTARG = bigint
);

create or replace function mysql.byteaCondAndBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaCondAndByteaCImp'
language c immutable strict;
drop operator if exists mysql.&&(bytea, bytea);
create operator mysql.&& (
    function = mysql.byteaCondAndBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaCondOrBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaCondOrByteaCImp'
language c immutable;
drop operator if exists mysql.||(bytea, bytea);
create operator mysql.|| (
    function = mysql.byteaCondOrBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaGtBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaGtByteaCImp'
language c immutable strict;
drop operator if exists mysql.>(bytea, bytea);
create operator mysql.> (
    function = mysql.byteaGtBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaGeBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaGeByteaCImp'
language c immutable strict;
drop operator if exists mysql.>=(bytea, bytea);
create operator mysql.>= (
    function = mysql.byteaGeBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaLtBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaLtByteaCImp'
language c immutable strict;
drop operator if exists mysql.<(bytea, bytea);
create operator mysql.< (
    function = mysql.byteaLtBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaLeBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaLeByteaCImp'
language c immutable strict;
drop operator if exists mysql.<=(bytea, bytea);
create operator mysql.<= (
    function = mysql.byteaLeBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaRegexpBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaRegexpByteaCImp'
language c immutable strict;
drop operator if exists mysql.~*(bytea, bytea);
create operator mysql.~* (
    function = mysql.byteaRegexpBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaNregexpBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaNregexpByteaCImp'
language c immutable strict;
drop operator if exists mysql.!~*(bytea, bytea);
create operator mysql.!~* (
    function = mysql.byteaNregexpBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaRegexpbinBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaRegexpbinByteaCImp'
language c immutable strict;
drop operator if exists mysql.~(bytea, bytea);
create operator mysql.~ (
    function = mysql.byteaRegexpbinBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaNregexpbinBytea(bytea, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaNregexpbinByteaCImp'
language c immutable strict;
drop operator if exists mysql.!~(bytea, bytea);
create operator mysql.!~ (
    function = mysql.byteaNregexpbinBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaPlBytea(bytea, bytea)
returns numeric
as '$libdir/mysm', 'byteaPlByteaCImp'
language c immutable strict;
DROP OPERATOR IF EXISTS mysql.+(bytea, bytea);
create operator mysql.+ (
    function = mysql.byteaPlBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaMiBytea(bytea, bytea)
returns numeric
as '$libdir/mysm', 'byteaMiByteaCImp'
language c immutable strict;
drop operator if exists mysql.-(bytea, bytea);
create operator mysql.- (
    function = mysql.byteaMiBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaMulBytea(bytea, bytea)
returns numeric
as '$libdir/mysm', 'byteaMulByteaCImp'
language c immutable strict;
drop operator if exists mysql.*(bytea, bytea);
create operator mysql.* (
    function = mysql.byteaMulBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaDivBytea(bytea, bytea)
returns numeric
as '$libdir/mysm', 'byteaDivByteaCImp'
language c immutable strict;
drop operator if exists mysql./(bytea, bytea);
create operator mysql./ (
    function = mysql.byteaDivBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaModBytea(bytea, bytea)
returns numeric
as '$libdir/mysm', 'byteaModByteaCImp'
language c immutable strict;
drop operator if exists mysql.%(bytea, bytea);
create operator mysql.% (
    function = mysql.byteaModBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaAndBytea(bytea, bytea)
returns pg_catalog.int8
as '$libdir/mysm', 'byteaAndByteaCImp'
language c immutable strict;
drop operator if exists mysql.&(bytea, bytea);
create operator mysql.& (
    function = mysql.byteaAndBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.byteaOrBytea(bytea, bytea)
returns pg_catalog.int8
as '$libdir/mysm', 'byteaOrByteaCImp'
language c immutable strict;
drop operator if exists mysql.|(bytea, bytea);
create operator mysql.| (
    function = mysql.byteaOrBytea,
    leftarg = bytea,
    rightarg = bytea
);

create or replace function mysql.anycompatibleEqBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleEqByteaCImp'
language c immutable strict;
drop operator if exists mysql.=(pg_catalog.anycompatible, bytea);
create operator mysql.= (
    function = mysql.anycompatibleEqBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaEqAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaEqAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.=(bytea, pg_catalog.anycompatible);
create operator mysql.= (
    function = mysql.byteaEqAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleNeBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleNeByteaCImp'
language c immutable strict;
drop operator if exists mysql.!=(pg_catalog.anycompatible, bytea);
create operator mysql.!= (
    function = mysql.anycompatibleNeBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);
drop operator if exists mysql.<>(pg_catalog.anycompatible, bytea);
create operator mysql.<> (
    function = mysql.anycompatibleNeBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaNeAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaNeAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.!=(bytea, pg_catalog.anycompatible);
create operator mysql.!= (
    function = mysql.byteaNeAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);
drop operator if exists mysql.<>(bytea, pg_catalog.anycompatible);
create operator mysql.<> (
    function = mysql.byteaNeAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleGtBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleGtByteaCImp'
language c immutable strict;
drop operator if exists mysql.>(pg_catalog.anycompatible, bytea);
create operator mysql.> (
    function = mysql.anycompatibleGtBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaGtAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaGtAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.>(bytea, pg_catalog.anycompatible);
create operator mysql.> (
    function = mysql.byteaGtAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleGeBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleGeByteaCImp'
language c immutable strict;
drop operator if exists mysql.>=(pg_catalog.anycompatible, bytea);
create operator mysql.>= (
    function = mysql.anycompatibleGeBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaGeAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaGeAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.>=(bytea, pg_catalog.anycompatible);
create operator mysql.>= (
    function = mysql.byteaGeAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleLtBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleLtByteaCImp'
language c immutable strict;
drop operator if exists mysql.<(pg_catalog.anycompatible, bytea);
create operator mysql.< (
    function = mysql.anycompatibleLtBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaLtAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaLtAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.<(bytea, pg_catalog.anycompatible);
create operator mysql.< (
    function = mysql.byteaLtAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleLeBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleLeByteaCImp'
language c immutable strict;
drop operator if exists mysql.<=(pg_catalog.anycompatible, bytea);
create operator mysql.<= (
    function = mysql.anycompatibleLeBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaLeAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaLeAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.<=(bytea, pg_catalog.anycompatible);
create operator mysql.<= (
    function = mysql.byteaLeAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleCondAndBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleCondAndByteaCImp'
language c immutable strict;
drop operator if exists mysql.&&(pg_catalog.anycompatible, bytea);
create operator mysql.&& (
    function = mysql.anycompatibleCondAndBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaCondAndAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaCondAndAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.&&(bytea, pg_catalog.anycompatible);
create operator mysql.&& (
    function = mysql.byteaCondAndAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleCondOrBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleCondOrByteaCImp'
language c immutable;
drop operator if exists mysql.||(pg_catalog.anycompatible, bytea);
create operator mysql.|| (
    function = mysql.anycompatibleCondOrBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaCondOrAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaCondOrAnycompatibleCImp'
language c immutable;
drop operator if exists mysql.||(bytea, pg_catalog.anycompatible);
create operator mysql.|| (
    function = mysql.byteaCondOrAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleLikeBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleLikeByteaCImp'
language c immutable strict;
drop operator if exists mysql.~~(pg_catalog.anycompatible, bytea);
create operator mysql.~~ (
    function = mysql.anycompatibleLikeBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaLikeAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaLikeAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.~~(bytea, pg_catalog.anycompatible);
create operator mysql.~~ (
    function = mysql.byteaLikeAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleNlikeBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleNlikeByteaCImp'
language c immutable strict;
drop operator if exists mysql.!~~(pg_catalog.anycompatible, bytea);
create operator mysql.!~~ (
    function = mysql.anycompatibleNlikeBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaNlikeAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaNlikeAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.!~~(bytea, pg_catalog.anycompatible);
create operator mysql.!~~ (
    function = mysql.byteaNlikeAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleRegexpBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleRegexpByteaCImp'
language c immutable strict;
drop operator if exists mysql.~*(pg_catalog.anycompatible, bytea);
create operator mysql.~* (
    function = mysql.anycompatibleRegexpBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaRegexpAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaRegexpAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.~*(bytea, pg_catalog.anycompatible);
create operator mysql.~* (
    function = mysql.byteaRegexpAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleNregexpBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleNregexpByteaCImp'
language c immutable strict;
drop operator if exists mysql.!~*(pg_catalog.anycompatible, bytea);
create operator mysql.!~* (
    function = mysql.anycompatibleNregexpBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaNregexpAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaNregexpAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.!~*(bytea, pg_catalog.anycompatible);
create operator mysql.!~* (
    function = mysql.byteaNregexpAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleRegexpbinBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleRegexpbinByteaCImp'
language c immutable strict;
drop operator if exists mysql.~(pg_catalog.anycompatible, bytea);
create operator mysql.~ (
    function = mysql.anycompatibleRegexpbinBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaRegexpbinAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaRegexpbinAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.~(bytea, pg_catalog.anycompatible);
create operator mysql.~ (
    function = mysql.byteaRegexpbinAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleNregexpbinBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.bool
as '$libdir/mysm', 'anycompatibleNregexpbinByteaCImp'
language c immutable strict;
drop operator if exists mysql.!~(pg_catalog.anycompatible, bytea);
create operator mysql.!~ (
    function = mysql.anycompatibleNregexpbinBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaNregexpbinAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.bool
as '$libdir/mysm', 'byteaNregexpbinAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.!~(bytea, pg_catalog.anycompatible);
create operator mysql.!~ (
    function = mysql.byteaNregexpbinAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatiblePlBytea(pg_catalog.anycompatible, bytea)
returns numeric
as '$libdir/mysm', 'anycompatiblePlByteaCImp'
language c immutable strict;
drop operator if exists mysql.+(pg_catalog.anycompatible, bytea);
create operator mysql.+ (
    function = mysql.anycompatiblePlBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaPlAnycompatible(bytea, pg_catalog.anycompatible)
returns numeric
as '$libdir/mysm', 'byteaPlAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.+(bytea, pg_catalog.anycompatible);
create operator mysql.+ (
    function = mysql.byteaPlAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleMiBytea(pg_catalog.anycompatible, bytea)
returns numeric
as '$libdir/mysm', 'anycompatibleMiByteaCImp'
language c immutable strict;
drop operator if exists mysql.-(pg_catalog.anycompatible, bytea);
create operator mysql.- (
    function = mysql.anycompatibleMiBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaMiAnycompatible(bytea, pg_catalog.anycompatible)
returns numeric
as '$libdir/mysm', 'byteaMiAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.-(bytea, pg_catalog.anycompatible);
create operator mysql.- (
    function = mysql.byteaMiAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleMulBytea(pg_catalog.anycompatible, bytea)
returns numeric
as '$libdir/mysm', 'anycompatibleMulByteaCImp'
language c immutable strict;
drop operator if exists mysql.*(pg_catalog.anycompatible, bytea);
create operator mysql.* (
    function = mysql.anycompatibleMulBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaMulAnycompatible(bytea, pg_catalog.anycompatible)
returns numeric
as '$libdir/mysm', 'byteaMulAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.*(bytea, pg_catalog.anycompatible);
create operator mysql.* (
    function = mysql.byteaMulAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleDivBytea(pg_catalog.anycompatible, bytea)
returns numeric
as '$libdir/mysm', 'anycompatibleDivByteaCImp'
language c immutable strict;
drop operator if exists mysql./(pg_catalog.anycompatible, bytea);
create operator mysql./ (
    function = mysql.anycompatibleDivBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaDivAnycompatible(bytea, pg_catalog.anycompatible)
returns numeric
as '$libdir/mysm', 'byteaDivAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql./(bytea, pg_catalog.anycompatible);
create operator mysql./ (
    function = mysql.byteaDivAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleModBytea(pg_catalog.anycompatible, bytea)
returns numeric
as '$libdir/mysm', 'anycompatibleModByteaCImp'
language c immutable strict;
drop operator if exists mysql.%(pg_catalog.anycompatible, bytea);
create operator mysql.% (
    function = mysql.anycompatibleModBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaModAnycompatible(bytea, pg_catalog.anycompatible)
returns numeric
as '$libdir/mysm', 'byteaModAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.%(bytea, pg_catalog.anycompatible);
create operator mysql.% (
    function = mysql.byteaModAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleAndBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.int8
as '$libdir/mysm', 'anycompatibleAndByteaCImp'
language c immutable strict;
drop operator if exists mysql.&(pg_catalog.anycompatible, bytea);
create operator mysql.& (
    function = mysql.anycompatibleAndBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaAndAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.int8
as '$libdir/mysm', 'byteaAndAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.&(bytea, pg_catalog.anycompatible);
create operator mysql.& (
    function = mysql.byteaAndAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

create or replace function mysql.anycompatibleOrBytea(pg_catalog.anycompatible, bytea)
returns pg_catalog.int8
as '$libdir/mysm', 'anycompatibleOrByteaCImp'
language c immutable strict;
drop operator if exists mysql.|(pg_catalog.anycompatible, bytea);
create operator mysql.| (
    function = mysql.anycompatibleOrBytea,
    leftarg = pg_catalog.anycompatible,
    rightarg = bytea
);

create or replace function mysql.byteaOrAnycompatible(bytea, pg_catalog.anycompatible)
returns pg_catalog.int8
as '$libdir/mysm', 'byteaOrAnycompatibleCImp'
language c immutable strict;
drop operator if exists mysql.|(bytea, pg_catalog.anycompatible);
create operator mysql.| (
    function = mysql.byteaOrAnycompatible,
    leftarg = bytea,
    rightarg = pg_catalog.anycompatible
);

CREATE OR REPLACE FUNCTION mysql.bit_eq_boolean(pg_catalog.bit, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    if $2 = true THEN
        if pg_catalog.int8($1) = 1 then
            return true;
        else
            return false;
        end if;
    else
        if pg_catalog.int8($1) = 0 then
            return true;
        else
            return false;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.bit_eq_boolean,
    LEFTARG = pg_catalog.bit,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolean_eq_bit(pg_catalog.bool, pg_catalog.bit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1 = true THEN
        if pg_catalog.int8($2) = 1 then
            return true;
        else
            return false;
        end if;
    else
        if pg_catalog.int8($2) = 0 then
            return true;
        else
            return false;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.boolean_eq_bit,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.bit
);

CREATE OR REPLACE FUNCTION mysql.varbit_eq_boolean(pg_catalog.varbit, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    if $2 = true THEN
        if pg_catalog.int8($1) = 1 then
            return true;
        else
            return false;
        end if;
    else
        if pg_catalog.int8($1) = 0 then
            return true;
        else
            return false;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.varbit_eq_boolean,
    LEFTARG = pg_catalog.varbit,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.boolean_eq_varbit(pg_catalog.bool, pg_catalog.varbit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1 = true THEN
        if pg_catalog.int8($2) = 1 then
            return true;
        else
            return false;
        end if;
    else
        if pg_catalog.int8($2) = 0 then
            return true;
        else
            return false;
        end if;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.boolean_eq_varbit,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.varbit
);

CREATE OR REPLACE FUNCTION mysql.varbit_eq_int4(pg_catalog.varbit, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    if pg_catalog.int8($1) = $2::pg_catalog.int8 then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.varbit_eq_int4,
    LEFTARG = pg_catalog.varbit,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int4_eq_varbit(pg_catalog.int4, pg_catalog.varbit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1::pg_catalog.int8 = pg_catalog.int8($2) THEN
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int4_eq_varbit,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.varbit
);

CREATE OR REPLACE FUNCTION mysql.varbit_eq_int2(pg_catalog.varbit, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    if pg_catalog.int8($1) = $2::pg_catalog.int8 then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.varbit_eq_int2,
    LEFTARG = pg_catalog.varbit,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int2_eq_varbit(pg_catalog.int2, pg_catalog.varbit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1::pg_catalog.int8 = pg_catalog.int8($2) THEN
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int2_eq_varbit,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.varbit
);

CREATE OR REPLACE FUNCTION mysql.varbit_eq_int8(pg_catalog.varbit, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if pg_catalog.int8($1) = $2 then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.varbit_eq_int8,
    LEFTARG = pg_catalog.varbit,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int8_eq_varbit(pg_catalog.int8, pg_catalog.varbit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1 = pg_catalog.int8($2) THEN
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int8_eq_varbit,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.varbit
);

CREATE OR REPLACE FUNCTION mysql.int2LeftmoveInt2(pg_catalog.int2, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int2, pg_catalog.int2);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int2LeftmoveInt2,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int2LeftmoveInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
    ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret * 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            raise EXCEPTION 'bigint out of range';
            -- MySQL有 unsigned bigit，Halo没有
            -- return 18446744073709551600 - ((0 - $1) << $2::pg_catalog.int4);
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int2, pg_catalog.int4);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int2LeftmoveInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int2LeftmoveInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int2, pg_catalog.int8);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int2LeftmoveInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int4LeftmoveInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int4LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int4, pg_catalog.int2);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int4LeftmoveInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int4LeftmoveInt4(pg_catalog.int4, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
    ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret * 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            raise EXCEPTION 'bigint out of range';
            -- MySQL有 unsigned bigit，Halo没有
            -- return 18446744073709551600 - ((0 - $1) << $2::pg_catalog.int4);
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int, pg_catalog.int4);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int4LeftmoveInt4,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int4LeftmoveInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int4LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int4, pg_catalog.int8);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int4LeftmoveInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int8LeftmoveInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int8, pg_catalog.int2);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int8LeftmoveInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int8LeftmoveInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
    ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret * 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            raise EXCEPTION 'bigint out of range';
            -- MySQL有 unsigned bigit，Halo没有
            -- return 18446744073709551600 - ((0 - $1) << $2::pg_catalog.int4);
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int8, pg_catalog.int4);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int8LeftmoveInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int8LeftmoveInt8(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int8LeftmoveInt8,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int2RightmoveInt2(pg_catalog.int2, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int2, pg_catalog.int2);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int2RightmoveInt2,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int2RightmoveInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
    ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret / 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            if 0 <= $2 then
                raise EXCEPTION 'bigint out of range';
                -- MySQL有 unsigned bigit，Halo没有
                -- return 18446744073709551600 - ((0 - $1) >> $2::pg_catalog.int4);
            else
                return 0;
            end if;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int2, pg_catalog.int4);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int2RightmoveInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int2RightmoveInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int2, pg_catalog.int8);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int2RightmoveInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int4RightmoveInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int4RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int4, pg_catalog.int2);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int4RightmoveInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int4RightmoveInt4(pg_catalog.int4, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
    ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret / 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            if 0 <= $2 then
                raise EXCEPTION 'bigint out of range';
                -- MySQL有 unsigned bigit，Halo没有
                -- return 18446744073709551600 - ((0 - $1) >> $2::pg_catalog.int4);
            else
                return 0;
            end if;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int, pg_catalog.int4);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int4RightmoveInt4,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int4RightmoveInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int4RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int4, pg_catalog.int8);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int4RightmoveInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int8RightmoveInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int8, pg_catalog.int2);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int8RightmoveInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int8RightmoveInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
    ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret / 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            if 0 <= $2 then
                raise EXCEPTION 'bigint out of range';
                -- MySQL有 unsigned bigit，Halo没有
                -- return 18446744073709551600 - ((0 - $1) >> $2::pg_catalog.int4);
            else
                return 0;
            end if;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int8, pg_catalog.int4);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int8RightmoveInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int8RightmoveInt8(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int8RightmoveInt8,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int2AndInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1::pg_catalog.int4 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int2, pg_catalog.int4);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int2AndInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int2AndInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int2, pg_catalog.int8);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int2AndInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int4AndInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1 & $2::pg_catalog.int4;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int4, pg_catalog.int2);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int4AndInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int4AndInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int4, pg_catalog.int8);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int4AndInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int8AndInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int8, pg_catalog.int2);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int8AndInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int8AndInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int8, pg_catalog.int4);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int8AndInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int2AndNumeric(pg_catalog.int2, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int2, pg_catalog.numeric);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int2AndNumeric,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.numeric
);

CREATE OR REPLACE FUNCTION mysql.int4AndNumeric(pg_catalog.int4, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int4, pg_catalog.numeric);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int4AndNumeric,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.numeric
);

CREATE OR REPLACE FUNCTION mysql.int8AndNumeric(pg_catalog.int8, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 & round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int8, pg_catalog.numeric);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int8AndNumeric,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.numeric
);

CREATE OR REPLACE FUNCTION mysql.numericAndInt2(pg_catalog.numeric, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.numeric, pg_catalog.int2);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.numericAndInt2,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.numericAndInt4(pg_catalog.numeric, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.numeric, pg_catalog.int4);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.numericAndInt4,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.numericAndInt8(pg_catalog.numeric, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.numeric, pg_catalog.int8);
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.numericAndInt8,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int2OrInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1::pg_catalog.int4 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int2, pg_catalog.int4);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int2OrInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int2OrInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int2, pg_catalog.int8);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int2OrInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int4OrInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1 | $2::pg_catalog.int4;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int4, pg_catalog.int2);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int4OrInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int4OrInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int4, pg_catalog.int8);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int4OrInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int8OrInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int8, pg_catalog.int2);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int8OrInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.int8OrInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int8, pg_catalog.int4);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int8OrInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int2OrNumeric(pg_catalog.int2, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int2, pg_catalog.numeric);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int2OrNumeric,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.numeric
);

CREATE OR REPLACE FUNCTION mysql.int4OrNumeric(pg_catalog.int4, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int4, pg_catalog.numeric);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int4OrNumeric,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.numeric
);

CREATE OR REPLACE FUNCTION mysql.int8OrNumeric(pg_catalog.int8, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 | round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int8, pg_catalog.numeric);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int8OrNumeric,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.numeric
);

CREATE OR REPLACE FUNCTION mysql.numericOrInt2(pg_catalog.numeric, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.numeric, pg_catalog.int2);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.numericOrInt2,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.numericOrInt4(pg_catalog.numeric, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.numeric, pg_catalog.int4);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.numericOrInt4,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.numericOrInt8(pg_catalog.numeric, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.numeric, pg_catalog.int8);
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.numericOrInt8,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int8
);

DROP OPERATOR IF EXISTS mysql.=(mysql.smallint, pg_catalog.bool);
DROP FUNCTION IF EXISTS mysql.int2EqBool(mysql.smallint, pg_catalog.bool);
CREATE OR REPLACE FUNCTION mysql.int2EqBool(pg_catalog.int2, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return true;
    elsif ($1 = 0) and ($2 = false) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.int2, pg_catalog.bool);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int2EqBool,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.bool
);

DROP OPERATOR IF EXISTS mysql.=(pg_catalog.bool, mysql.smallint);
DROP FUNCTION IF EXISTS mysql.boolEqInt2(pg_catalog.bool, mysql.smallint);
CREATE OR REPLACE FUNCTION mysql.boolEqInt2(pg_catalog.bool, pg_catalog.int2)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return true;
    elsif ($1 = false) and ($2 = 0) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.bool, pg_catalog.int2);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.boolEqInt2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int2
);

DROP OPERATOR IF EXISTS mysql.<>(mysql.smallint, pg_catalog.bool);
DROP FUNCTION IF EXISTS mysql.int2NeBool(mysql.smallint, pg_catalog.bool);
CREATE OR REPLACE FUNCTION mysql.int2NeBool(pg_catalog.int2, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return false;
    elsif ($1 = 0) and ($2 = false) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.int2NeBool,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.bool
);

DROP OPERATOR IF EXISTS mysql.<>(pg_catalog.bool, mysql.smallint);
DROP FUNCTION IF EXISTS mysql.boolNeInt2(pg_catalog.bool, mysql.smallint);
CREATE OR REPLACE FUNCTION mysql.boolNeInt2(pg_catalog.bool, pg_catalog.int2)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return false;
    elsif ($1 = false) and ($2 = 0) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.boolNeInt2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.bigint_bitxor_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 # $2;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.^#(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.^# (
    FUNCTION = mysql.bigint_bitxor_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.bigint_xor_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int2
AS
$$
BEGIN
    if ((($1 = 0) and ($2 != 0)) or (($1 != 0) and ($2 = 0))) then
        return 1;
    else
        return 0;
    end if;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.^^(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.^^ (
    FUNCTION = mysql.bigint_xor_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.text_and_text(pg_catalog.text, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 is null) and ($2 is null)) then
        return null;
    else
        raise EXCEPTION 'invalid parameters';
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.text, pg_catalog.text);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.text_and_text,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.bigint_and_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 = 0::pg_catalog.int8) or ($2 = 0::pg_catalog.int8)) then
        return false;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return true;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.bigint_and_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.text_or_anynoarray(pg_catalog.text, pg_catalog.anynonarray)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is not null) then
        return $1 operator(pg_catalog.||) $2;
    else
        if $2::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
        return 0::pg_catalog.int8 operator(mysql.||) $2::pg_catalog.int8;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.text, pg_catalog.anynonarray);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.text_or_anynoarray,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.anynonarray
);

CREATE OR REPLACE FUNCTION mysql.anynonarray_or_text(pg_catalog.anynonarray, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($2 is not null) then
        return $1 operator(pg_catalog.||) $2;
    else
        if $1::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.anynonarray, pg_catalog.text);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.anynonarray_or_text,
    LEFTARG = pg_catalog.anynonarray,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.bigint_or_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if ((($1 is not null) and ($1 != 0::pg_catalog.int8)) or
        (($2 is not null) and ($2 != 0::pg_catalog.int8))) then
        return true;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return false;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.bigint_or_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql._add_bool(pg_catalog.bool)
returns pg_catalog.int2
AS
$$
BEGIN
    return $1::pg_catalog.int2;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.+(none, pg_catalog.bool);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql._add_bool,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql._add_null(pg_catalog.text)
returns pg_catalog.int2
AS
$$
BEGIN
    raise EXCEPTION 'invalid parameters';
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.+(none, pg_catalog.text);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql._add_null,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql._sub_bool(pg_catalog.bool)
returns pg_catalog.int2
AS
$$
BEGIN
    return 0 - $1::pg_catalog.int2;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.-(none, pg_catalog.bool);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql._sub_bool,
    RIGHTARG = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql._sub_null(pg_catalog.text)
returns pg_catalog.int2
AS
$$
BEGIN
    raise EXCEPTION 'invalid parameters';
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.-(none, pg_catalog.text);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql._sub_null,
    RIGHTARG = pg_catalog.text
);

DROP OPERATOR IF EXISTS mysql.= (pg_catalog.varbit, pg_catalog.int4) cascade;
DROP FUNCTION IF EXISTS mysql.varbit_eq_int4(pg_catalog.varbit, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.varbit_eq_int4(pg_catalog.varbit, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    if pg_catalog.int8($1) = $2::pg_catalog.int8 then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.varbit_eq_int4,
    LEFTARG = pg_catalog.varbit,
    RIGHTARG = pg_catalog.int4
);

DROP OPERATOR IF EXISTS mysql.= (pg_catalog.int4, pg_catalog.varbit);
DROP FUNCTION IF EXISTS mysql.int4_eq_varbit(pg_catalog.int4, pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_eq_varbit(pg_catalog.int4, pg_catalog.varbit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1::pg_catalog.int8 = pg_catalog.int8($2) THEN
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int4_eq_varbit,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.varbit
);

DROP OPERATOR IF EXISTS mysql.= (pg_catalog.varbit, pg_catalog.int2);
DROP FUNCTION IF EXISTS mysql.varbit_eq_int2(pg_catalog.varbit, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.varbit_eq_int2(pg_catalog.varbit, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    if pg_catalog.int8($1) = $2::pg_catalog.int8 then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.varbit_eq_int2,
    LEFTARG = pg_catalog.varbit,
    RIGHTARG = pg_catalog.int2
);

DROP OPERATOR IF EXISTS mysql.= (pg_catalog.int2, pg_catalog.varbit);
DROP FUNCTION IF EXISTS mysql.int2_eq_varbit(pg_catalog.int2, pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_eq_varbit(pg_catalog.int2, pg_catalog.varbit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1::pg_catalog.int8 = pg_catalog.int8($2) THEN
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int2_eq_varbit,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.varbit
);

DROP OPERATOR IF EXISTS mysql.= (pg_catalog.varbit, pg_catalog.int8);
DROP FUNCTION IF EXISTS mysql.varbit_eq_int8(pg_catalog.varbit, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.varbit_eq_int8(pg_catalog.varbit, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if pg_catalog.int8($1) = $2 then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.varbit_eq_int8,
    LEFTARG = pg_catalog.varbit,
    RIGHTARG = pg_catalog.int8
);

DROP OPERATOR IF EXISTS mysql.= (pg_catalog.int8, pg_catalog.varbit);
DROP FUNCTION IF EXISTS mysql.int8_eq_varbit(pg_catalog.int8, pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.int8_eq_varbit(pg_catalog.int8, pg_catalog.varbit)
returns pg_catalog.bool
AS
$$
BEGIN
    if $1 = pg_catalog.int8($2) THEN
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int8_eq_varbit,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.varbit
);

DROP FUNCTION IF EXISTS mysql.int2LeftmoveInt2(pg_catalog.int2, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int2LeftmoveInt2(pg_catalog.int2, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int2, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int2LeftmoveInt2,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int2LeftmoveInt4(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int2LeftmoveInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret * 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            raise EXCEPTION 'bigint out of range';
            -- MySQL有 unsigned bigit，Halo没有
            -- return 18446744073709551600 - ((0 - $1) << $2::pg_catalog.int4);
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int2LeftmoveInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2LeftmoveInt8(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int2LeftmoveInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int2LeftmoveInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

CREATE OR REPLACE FUNCTION mysql.int4LeftmoveInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
        return mysql.int4LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int4, pg_catalog.int2);
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int4LeftmoveInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int4LeftmoveInt4(pg_catalog.int4, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int4LeftmoveInt4(pg_catalog.int4, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret * 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            raise EXCEPTION 'bigint out of range';
            -- MySQL有 unsigned bigit，Halo没有
            -- return 18446744073709551600 - ((0 - $1) << $2::pg_catalog.int4);
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int4LeftmoveInt4,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int4LeftmoveInt8(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int4LeftmoveInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int4LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int4LeftmoveInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int8LeftmoveInt2(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int8LeftmoveInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int8LeftmoveInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int8LeftmoveInt4(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int8LeftmoveInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret * 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            raise EXCEPTION 'bigint out of range';
            -- MySQL有 unsigned bigit，Halo没有
            -- return 18446744073709551600 - ((0 - $1) << $2::pg_catalog.int4);
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int8LeftmoveInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int8LeftmoveInt8(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int8LeftmoveInt8(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8LeftmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<<(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.<< (
    FUNCTION = mysql.int8LeftmoveInt8,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int2RightmoveInt2(pg_catalog.int2, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int2RightmoveInt2(pg_catalog.int2, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int2, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int2RightmoveInt2,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int2RightmoveInt4(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int2RightmoveInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret / 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            if 0 <= $2 then
                raise EXCEPTION 'bigint out of range';
                -- MySQL有 unsigned bigit，Halo没有
                -- return 18446744073709551600 - ((0 - $1) >> $2::pg_catalog.int4);
            else
                return 0;
            end if;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int2RightmoveInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2RightmoveInt8(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int2RightmoveInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int2RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int2RightmoveInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int4RightmoveInt2(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int4RightmoveInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int4RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int4RightmoveInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int4RightmoveInt4(pg_catalog.int4, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int4RightmoveInt4(pg_catalog.int4, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret / 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            if 0 <= $2 then
                raise EXCEPTION 'bigint out of range';
                -- MySQL有 unsigned bigit，Halo没有
                -- return 18446744073709551600 - ((0 - $1) >> $2::pg_catalog.int4);
            else
                return 0;
            end if;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int4RightmoveInt4,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int4RightmoveInt8(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int4RightmoveInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int4RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int4RightmoveInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int8RightmoveInt2(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int8RightmoveInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int8RightmoveInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int8RightmoveInt4(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int8RightmoveInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
DECLARE
ret pg_catalog.int8;
BEGIN
    if $1 is not null and $2 is not null then
        if 0 <= $1 then
            if 0 <= $2 then
                ret = $1;
                for i in 1..$2 loop
                    ret = ret / 2;
                end loop;
                return ret;
            else
                return 0;
            end if;
        else
            if 0 <= $2 then
                raise EXCEPTION 'bigint out of range';
                -- MySQL有 unsigned bigit，Halo没有
                -- return 18446744073709551600 - ((0 - $1) >> $2::pg_catalog.int4);
            else
                return 0;
            end if;
        end if;
    else
        return null;
    end if;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int8RightmoveInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int8RightmoveInt8(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int8RightmoveInt8(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return mysql.int8RightmoveInt4($1, $2::pg_catalog.int4);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>>(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.>> (
    FUNCTION = mysql.int8RightmoveInt8,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int2AndInt4(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int2AndInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1::pg_catalog.int4 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int2AndInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2AndInt8(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int2AndInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int2AndInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int4AndInt2(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int4AndInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1 & $2::pg_catalog.int4;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int4AndInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int4AndInt8(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int4AndInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int4AndInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int8AndInt2(pg_catalog.int8, pg_catalog.int2) CASCADE;
CREATE OR REPLACE FUNCTION mysql.int8AndInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int8AndInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int8AndInt4(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int8AndInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int8AndInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2AndNumeric(pg_catalog.int2, pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.int2AndNumeric(pg_catalog.int2, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int2, pg_catalog.numeric) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int2AndNumeric,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.numeric
);

DROP FUNCTION IF EXISTS mysql.int4AndNumeric(pg_catalog.int4, pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.int4AndNumeric(pg_catalog.int4, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 & round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int4, pg_catalog.numeric) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int4AndNumeric,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.numeric
);

DROP FUNCTION IF EXISTS mysql.int8AndNumeric(pg_catalog.int8, pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.int8AndNumeric(pg_catalog.int8, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 & round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int8, pg_catalog.numeric) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.int8AndNumeric,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.numeric
);

DROP FUNCTION IF EXISTS mysql.numericAndInt2(pg_catalog.numeric, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.numericAndInt2(pg_catalog.numeric, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
        return round($1)::pg_catalog.int8 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.numeric, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.numericAndInt2,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.numericAndInt4(pg_catalog.numeric, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.numericAndInt4(pg_catalog.numeric, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 & $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.numeric, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.numericAndInt4,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.numericAndInt8(pg_catalog.numeric, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.numericAndInt8(pg_catalog.numeric, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 & $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.numeric, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.& (
    FUNCTION = mysql.numericAndInt8,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int2OrInt4(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int2OrInt4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1::pg_catalog.int4 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int2OrInt4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2OrInt8(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int2OrInt8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int2OrInt8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int4OrInt2(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int4OrInt2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.int4
AS
$$
BEGIN
    return $1 | $2::pg_catalog.int4;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int4OrInt2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2

);

DROP FUNCTION IF EXISTS mysql.int4OrInt8(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int4OrInt8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int4OrInt8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int8OrInt2(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int8OrInt2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int8OrInt2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int8OrInt4(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int8OrInt4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int8OrInt4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2OrNumeric(pg_catalog.int2, pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.int2OrNumeric(pg_catalog.int2, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int2, pg_catalog.numeric) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int2OrNumeric,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.numeric
);

DROP FUNCTION IF EXISTS mysql.int4OrNumeric(pg_catalog.int4, pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.int4OrNumeric(pg_catalog.int4, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1::pg_catalog.int8 | round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int4, pg_catalog.numeric) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int4OrNumeric,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.numeric
);

DROP FUNCTION IF EXISTS mysql.int8OrNumeric(pg_catalog.int8, pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.int8OrNumeric(pg_catalog.int8, pg_catalog.numeric)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 | round($2)::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.int8, pg_catalog.numeric) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.int8OrNumeric,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.numeric
);

DROP FUNCTION IF EXISTS mysql.numericOrInt2(pg_catalog.numeric, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.numericOrInt2(pg_catalog.numeric, pg_catalog.int2)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.numeric, pg_catalog.int2) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.numericOrInt2,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.numericOrInt4(pg_catalog.numeric, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.numericOrInt4(pg_catalog.numeric, pg_catalog.int4)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 | $2::pg_catalog.int8;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.numeric, pg_catalog.int4) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.numericOrInt4,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.numericOrInt8(pg_catalog.numeric, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.numericOrInt8(pg_catalog.numeric, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return round($1)::pg_catalog.int8 | $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.|(pg_catalog.numeric, pg_catalog.int8) cascade;
CREATE OPERATOR mysql.| (
    FUNCTION = mysql.numericOrInt8,
    LEFTARG = pg_catalog.numeric,
    RIGHTARG = pg_catalog.int8
);

DROP OPERATOR IF EXISTS mysql.=(mysql.smallint, pg_catalog.bool) cascade;
DROP FUNCTION IF EXISTS mysql.int2EqBool(mysql.smallint, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.int2EqBool(pg_catalog.int2, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return true;
    elsif ($1 = 0) and ($2 = false) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.int2, pg_catalog.bool) cascade;
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.int2EqBool,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.bool
);

DROP OPERATOR IF EXISTS mysql.=(pg_catalog.bool, mysql.smallint);
DROP FUNCTION IF EXISTS mysql.boolEqInt2(pg_catalog.bool, mysql.smallint);
CREATE OR REPLACE FUNCTION mysql.boolEqInt2(pg_catalog.bool, pg_catalog.int2)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return true;
    elsif ($1 = false) and ($2 = 0) then
        return true;
    else
        return false;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.bool, pg_catalog.int2);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.boolEqInt2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int2
);

DROP OPERATOR IF EXISTS mysql.<>(mysql.smallint, pg_catalog.bool);
DROP FUNCTION IF EXISTS mysql.int2NeBool(mysql.smallint, pg_catalog.bool);
CREATE OR REPLACE FUNCTION mysql.int2NeBool(pg_catalog.int2, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = 1) and ($2 = true) then
        return false;
    elsif ($1 = 0) and ($2 = false) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
DROP OPERATOR IF EXISTS mysql.<> (pg_catalog.int2, pg_catalog.bool);
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.int2NeBool,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.bool
);

DROP OPERATOR IF EXISTS mysql.<>(pg_catalog.bool, mysql.smallint);
DROP FUNCTION IF EXISTS mysql.boolNeInt2(pg_catalog.bool, mysql.smallint);
CREATE OR REPLACE FUNCTION mysql.boolNeInt2(pg_catalog.bool, pg_catalog.int2)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if ($1 = true) and ($2 = 1) then
        return false;
    elsif ($1 = false) and ($2 = 0) then
        return false;
    else
        return true;
    end if;
END;
$$
LANGUAGE plpgsql STRICT;
DROP OPERATOR IF EXISTS mysql.<> (pg_catalog.bool, pg_catalog.int2);
CREATE OPERATOR mysql.<> (
    FUNCTION = mysql.boolNeInt2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.bigint_bitxor_bigint(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bigint_bitxor_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int8
AS
$$
BEGIN
    return $1 # $2;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.^#(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.^# (
    FUNCTION = mysql.bigint_bitxor_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.bigint_xor_bigint(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bigint_xor_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.int2
AS
$$
BEGIN
    if ((($1 = 0) and ($2 != 0)) or (($1 != 0) and ($2 = 0))) then
        return 1;
    else
        return 0;
    end if;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.^^(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.^^ (
    FUNCTION = mysql.bigint_xor_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.text_and_text(pg_catalog.text, pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.text_and_text(pg_catalog.text, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 is null) and ($2 is null)) then
        return null;
    else
        raise EXCEPTION 'invalid parameters';
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.text, pg_catalog.text);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.text_and_text,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.text
);

DROP FUNCTION IF EXISTS mysql.bigint_and_bigint(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bigint_and_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 = 0::pg_catalog.int8) or ($2 = 0::pg_catalog.int8)) then
        return false;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return true;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.bigint_and_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.text_or_anynoarray(pg_catalog.text, pg_catalog.anynonarray) cascade;
CREATE OR REPLACE FUNCTION mysql.text_or_anynoarray(pg_catalog.text, pg_catalog.anynonarray)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is not null) then
        return $1 operator(pg_catalog.||) $2;
    else
        if $2::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
        return 0::pg_catalog.int8 operator(mysql.||) $2::pg_catalog.int8;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.text, pg_catalog.anynonarray);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.text_or_anynoarray,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.anynonarray
);

DROP FUNCTION IF EXISTS mysql.anynonarray_or_text(pg_catalog.anynonarray, pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.anynonarray_or_text(pg_catalog.anynonarray, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($2 is not null) then
        return $1 operator(pg_catalog.||) $2;
    else
        if $1::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.anynonarray, pg_catalog.text);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.anynonarray_or_text,
    LEFTARG = pg_catalog.anynonarray,
    RIGHTARG = pg_catalog.text
);

DROP FUNCTION IF EXISTS mysql.bigint_or_bigint(pg_catalog.int8, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bigint_or_bigint(pg_catalog.int8, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if ((($1 is not null) and ($1 != 0::pg_catalog.int8)) or
        (($2 is not null) and ($2 != 0::pg_catalog.int8))) then
        return true;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return false;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int8, pg_catalog.int8);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.bigint_or_bigint,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql._add_bool(pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql._add_bool(pg_catalog.bool)
returns pg_catalog.int2
AS
$$
BEGIN
    return $1::pg_catalog.int2;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.+(none, pg_catalog.bool);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql._add_bool,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql._add_null(pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql._add_null(pg_catalog.text)
returns pg_catalog.int2
AS
$$
BEGIN
    raise EXCEPTION 'invalid parameters';
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.+(none, pg_catalog.text);
CREATE OPERATOR mysql.+ (
    FUNCTION = mysql._add_null,
    RIGHTARG = pg_catalog.text
);

DROP FUNCTION IF EXISTS mysql._sub_bool(pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql._sub_bool(pg_catalog.bool)
returns pg_catalog.int2
AS
$$
BEGIN
    return 0 - $1::pg_catalog.int2;
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.-(none, pg_catalog.bool);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql._sub_bool,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql._sub_null(pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql._sub_null(pg_catalog.text)
returns pg_catalog.int2
AS
$$
BEGIN
    raise EXCEPTION 'invalid parameters';
END;
$$
immutable strict language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.-(none, pg_catalog.text);
CREATE OPERATOR mysql.- (
    FUNCTION = mysql._sub_null,
    RIGHTARG = pg_catalog.text
);

create or replace function mysql.boolCondAndbool(pg_catalog.bool, pg_catalog.bool)
returns pg_catalog.bool
as '$libdir/mysm', 'boolCondAndboolCImp'
language c immutable;
create operator mysql.&& (
    function = mysql.boolCondAndbool,
    leftarg = pg_catalog.bool,
    rightarg = pg_catalog.bool
);

CREATE OR REPLACE FUNCTION mysql.int4_and_int4(pg_catalog.int4, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 = 0::pg_catalog.int4) or ($2 = 0::pg_catalog.int4)) then
        return false;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return true;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int4_and_int4,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int4
);

CREATE OR REPLACE FUNCTION mysql.int2_and_int2(pg_catalog.int2, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 = 0::pg_catalog.int2) or ($2 = 0::pg_catalog.int2)) then
        return false;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return true;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int2_and_int2,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int2
);

CREATE OR REPLACE FUNCTION mysql.bool_or_bool(pg_catalog.bool, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 is not null) and ($2 is not null)) then
        if (($1 != 0::pg_catalog.int2) or ($2 != 0::pg_catalog.int2)) then
            return true;
        else
            return false;
        end if;
    elsif (($1 is not null) and ($2 is null)) then
        if ($1 != 0::pg_catalog.int2) then
            return true;
        else
            return false;
        end if;
    elsif (($1 is null) and ($2 is not null)) then
        if ($2 != 0::pg_catalog.int2) then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.bool_or_bool,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql.int8_or_bool(pg_catalog.int8, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.int8_or_bool(pg_catalog.int8, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    if ((($1 is not null) and ($1 != 0)) or
        (($2 is not null) and ($2 != false))) then
        return true;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return false;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int8, pg_catalog.bool);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int8_or_bool,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql.int8_or_int2(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int8_or_int2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int8, pg_catalog.int2);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int8_or_int2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int8_or_int4(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int8_or_int4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int8, pg_catalog.int4);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int8_or_int4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2_or_bool(pg_catalog.int2, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_or_bool(pg_catalog.int2, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.int8_or_bool($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int2, pg_catalog.bool);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int2_or_bool,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql.int2_or_int2(pg_catalog.int2, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_or_int2(pg_catalog.int2, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1::pg_catalog.int8, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int2, pg_catalog.int2);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int2_or_int2,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int2_or_int4(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_or_int4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1::pg_catalog.int8, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int2, pg_catalog.int4);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int2_or_int4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2_or_int8(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_or_int8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int2, pg_catalog.int8);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int2_or_int8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int4_or_bool(pg_catalog.int4, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_or_bool(pg_catalog.int4, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.int8_or_bool($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int4, pg_catalog.bool);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int4_or_bool,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql.int4_or_int2(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_or_int2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1::pg_catalog.int8, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int4, pg_catalog.int2);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int4_or_int2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int4_or_int4(pg_catalog.int4, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_or_int4(pg_catalog.int4, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1::pg_catalog.int8, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int4, pg_catalog.int4);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int4_or_int4,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int4_or_int8(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_or_int8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_or_bigint($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.int4, pg_catalog.int8);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.int4_or_int8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.bool_or_int8(pg_catalog.bool, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bool_or_int8(pg_catalog.bool, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if ((($1 is not null) and ($1 != false)) or
        (($2 is not null) and ($2 != 0))) then
        return true;
    elsif (($1 is null) or ($2 is null)) then
        return null;
    else
        return false;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.bool, pg_catalog.int8);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.bool_or_int8,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.bool_or_int2(pg_catalog.bool, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.bool_or_int2(pg_catalog.bool, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.bool_or_int8($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.bool, pg_catalog.int2);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.bool_or_int2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.bool_or_int4(pg_catalog.bool, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.bool_or_int4(pg_catalog.bool, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.bool_or_int8($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.bool, pg_catalog.int4);
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.bool_or_int4,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int8_and_bool(pg_catalog.int8, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.int8_and_bool(pg_catalog.int8, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 is not null) and ($2 is not null)) then
        if (($1 != 0) and ($2 = true)) then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int8, pg_catalog.bool);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int8_and_bool,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql.int8_and_int2(pg_catalog.int8, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int8_and_int2(pg_catalog.int8, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_and_bigint($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int8, pg_catalog.int2);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int8_and_int2,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int8_and_int4(pg_catalog.int8, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int8_and_int4(pg_catalog.int8, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_and_bigint($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int8, pg_catalog.int4);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int8_and_int4,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2_and_bool(pg_catalog.int2, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_and_bool(pg_catalog.int2, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.int8_and_bool($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int2, pg_catalog.bool);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int2_and_bool,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql.int2_and_int4(pg_catalog.int2, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_and_int4(pg_catalog.int2, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_and_bigint($1::pg_catalog.int8, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int2, pg_catalog.int4);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int2_and_int4,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.int2_and_int8(pg_catalog.int2, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int2_and_int8(pg_catalog.int2, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_and_bigint($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int2, pg_catalog.int8);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int2_and_int8,
    LEFTARG = pg_catalog.int2,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.int4_and_bool(pg_catalog.int4, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_and_bool(pg_catalog.int4, pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.int8_and_bool($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int4, pg_catalog.bool);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int4_and_bool,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.bool
);

DROP FUNCTION IF EXISTS mysql.int4_and_int2(pg_catalog.int4, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_and_int2(pg_catalog.int4, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_and_bigint($1::pg_catalog.int8, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int4, pg_catalog.int2);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int4_and_int2,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.int4_and_int8(pg_catalog.int4, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.int4_and_int8(pg_catalog.int4, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    return bigint_and_bigint($1::pg_catalog.int8, $2);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.int4, pg_catalog.int8);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.int4_and_int8,
    LEFTARG = pg_catalog.int4,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.bool_and_int8(pg_catalog.bool, pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bool_and_int8(pg_catalog.bool, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    if (($1 is not null) and ($2 is not null)) then
        if (($1 = true) and ($2 != 0)) then
            return true;
        else
            return false;
        end if;
    else
        return null;
    end if;
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.bool, pg_catalog.int8);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.bool_and_int8,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int8
);

DROP FUNCTION IF EXISTS mysql.bool_and_int2(pg_catalog.bool, pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.bool_and_int2(pg_catalog.bool, pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.bool_and_int8($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.bool, pg_catalog.int2);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.bool_and_int2,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int2
);

DROP FUNCTION IF EXISTS mysql.bool_and_int4(pg_catalog.bool, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.bool_and_int4(pg_catalog.bool, pg_catalog.int4)
returns pg_catalog.bool
AS
$$
BEGIN
    return mysql.bool_and_int8($1, $2::pg_catalog.int8);
END;
$$
immutable language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.&&(pg_catalog.bool, pg_catalog.int4);
CREATE OPERATOR mysql.&& (
    FUNCTION = mysql.bool_and_int4,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.int4
);

DROP FUNCTION IF EXISTS mysql.bool_or_bool(pg_catalog.bool, pg_catalog.bool) cascade;
CREATE OR REPLACE FUNCTION mysql.bool_or_bool(pg_catalog.bool, pg_catalog.bool)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'boolOrBool'
LANGUAGE C IMMUTABLE;
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.bool_or_bool,
    LEFTARG = pg_catalog.bool,
    RIGHTARG = pg_catalog.bool
);

DROP OPERATOR IF EXISTS mysql.||(pg_catalog.text, pg_catalog.text);
DROP FUNCTION IF EXISTS mysql.text_or_text(pg_catalog.text, pg_catalog.text);
CREATE OR REPLACE FUNCTION mysql.text_or_text(pg_catalog.text, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        if ($2 is null) then
            return null;
        else
            if ($2::int8 != 0) then
                return true;
            else
                return null;
            end if;
        end if;
    else
        if ($2 is null) then
            if ($1::int8 != 0) then
                return true;
            else
                return null;
            end if;
        else
            return ($1::int8 != 0) || ($2::int8 != 0);
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.text_or_text,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.text
);

DROP OPERATOR IF EXISTS mysql.||(pg_catalog.anynonarray, pg_catalog.text);
DROP FUNCTION IF EXISTS mysql.anynonarray_or_text(pg_catalog.anynonarray, pg_catalog.text);
CREATE OR REPLACE FUNCTION mysql.anycompatiblenonarray_or_text(pg_catalog.anycompatiblenonarray, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        if ($2 is null) then
            return null;
        else
            if ($2::int8 != 0) then
                return true;
            else
                return null;
            end if;
        end if;
    else
        if ($2 is null) then
            if ($1::int8 != 0) then
                return true;
            else
                return null;
            end if;
        else
            return ($1::int8 != 0) || ($2::int8 != 0);
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.anycompatiblenonarray_or_text,
    LEFTARG = pg_catalog.anycompatiblenonarray,
    RIGHTARG = pg_catalog.text
);

DROP OPERATOR IF EXISTS mysql.||(pg_catalog.text, pg_catalog.anynonarray);
DROP FUNCTION IF EXISTS mysql.text_or_anynoarray(pg_catalog.text, pg_catalog.anynonarray);
CREATE OR REPLACE FUNCTION mysql.text_or_anycompatiblenonarray(pg_catalog.text, pg_catalog.anycompatiblenonarray)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        if ($2 is null) then
            return null;
        else
            if ($2::int8 != 0) then
                return true;
            else
                return null;
            end if;
        end if;
    else
        if ($2 is null) then
            if ($1::int8 != 0) then
                return true;
            else
                return null;
            end if;
        else
            return ($1::int8 != 0) || ($2::int8 != 0);
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.text_or_anycompatiblenonarray,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.anycompatiblenonarray
);

DROP OPERATOR IF EXISTS mysql.||(pg_catalog.text, pg_catalog.text);
DROP FUNCTION IF EXISTS mysql.text_or_text(pg_catalog.text, pg_catalog.text);
CREATE OR REPLACE FUNCTION mysql.text_or_text(pg_catalog.text, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        if ($2 is null) then
            return null;
        else
            if ($2::int8 != 0) then
                return true;
            else
                return null;
            end if;
        end if;
    else
        if ($2 is null) then
            if ($1::int8 != 0) then
                return true;
            else
                return null;
            end if;
        else
            return ($1::int8 != 0) || ($2::int8 != 0);
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.text_or_text,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.text
);

DROP OPERATOR IF EXISTS mysql.||(pg_catalog.anynonarray, pg_catalog.text);
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.anycompatiblenonarray, pg_catalog.text);
DROP FUNCTION IF EXISTS mysql.anynonarray_or_text(pg_catalog.anynonarray, pg_catalog.text);
CREATE OR REPLACE FUNCTION mysql.anycompatiblenonarray_or_text(pg_catalog.anycompatiblenonarray, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        if ($2 is null) then
            return null;
        else
            if ($2::int8 != 0) then
                return true;
            else
                return null;
            end if;
        end if;
    else
        if ($2 is null) then
            if ($1::int8 != 0) then
                return true;
            else
                return null;
            end if;
        else
            return ($1::int8 != 0) || ($2::int8 != 0);
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.anycompatiblenonarray_or_text,
    LEFTARG = pg_catalog.anycompatiblenonarray,
    RIGHTARG = pg_catalog.text
);

DROP OPERATOR IF EXISTS mysql.||(pg_catalog.text, pg_catalog.anynonarray);
DROP OPERATOR IF EXISTS mysql.||(pg_catalog.text, pg_catalog.anycompatiblenonarray);
DROP FUNCTION IF EXISTS mysql.text_or_anynoarray(pg_catalog.text, pg_catalog.anynonarray);
CREATE OR REPLACE FUNCTION mysql.text_or_anycompatiblenonarray(pg_catalog.text, pg_catalog.anycompatiblenonarray)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        if ($2 is null) then
            return null;
        else
            if ($2::int8 != 0) then
                return true;
            else
                return null;
            end if;
        end if;
    else
        if ($2 is null) then
            if ($1::int8 != 0) then
                return true;
            else
                return null;
            end if;
        else
            return ($1::int8 != 0) || ($2::int8 != 0);
        end if;
    end if;
END;
$$
immutable language 'plpgsql';
CREATE OPERATOR mysql.|| (
    FUNCTION = mysql.text_or_anycompatiblenonarray,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.anycompatiblenonarray
);

CREATE OR REPLACE FUNCTION mysql.timestamp_gt_text(pg_catalog.timestamp, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamp;
BEGIN
    tmp2 := $2::pg_catalog.timestamp;
    return ($1 > tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 > $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.timestamp_gt_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamptz_gt_text(pg_catalog.timestamptz, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamptz;
BEGIN
    tmp2 := $2::pg_catalog.timestamptz;
    return ($1 > tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 > $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.timestamptz, pg_catalog.text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.timestamptz_gt_text,
    LEFTARG = pg_catalog.timestamptz,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_ge_text(pg_catalog.timestamp, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamp;
BEGIN
    tmp2 := $2::pg_catalog.timestamp;
    return ($1 >= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 >= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.timestamp_ge_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_lt_text(pg_catalog.timestamp, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamp;
BEGIN
    tmp2 := $2::pg_catalog.timestamp;
    return ($1 < tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 < $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.timestamp_lt_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_le_text(pg_catalog.timestamp, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamp;
BEGIN
    tmp2 := $2::pg_catalog.timestamp;
    return ($1 <= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 <= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.timestamp_le_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_eq_text(pg_catalog.timestamp, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamp;
BEGIN
    tmp2 := $2::pg_catalog.timestamp;
    return ($1 = tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 = $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.timestamp_eq_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_ne_text(pg_catalog.timestamp, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamp;
BEGIN
    tmp2 := $2::pg_catalog.timestamp;
    return ($1 != tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 != $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.timestamp_ne_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamptz_ge_text(pg_catalog.timestamptz, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamptz;
BEGIN
    tmp2 := $2::pg_catalog.timestamptz;
    return ($1 >= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 >= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.timestamptz, pg_catalog.text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.timestamptz_ge_text,
    LEFTARG = pg_catalog.timestamptz,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamptz_lt_text(pg_catalog.timestamptz, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamptz;
BEGIN
    tmp2 := $2::pg_catalog.timestamptz;
    return ($1 < tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 < $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.timestamptz, pg_catalog.text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.timestamptz_lt_text,
    LEFTARG = pg_catalog.timestamptz,
    RIGHTARG = pg_catalog.text
);


CREATE OR REPLACE FUNCTION mysql.timestamptz_le_text(pg_catalog.timestamptz, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamptz;
BEGIN
    tmp2 := $2::pg_catalog.timestamptz;
    return ($1 <= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 <= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.timestamptz, pg_catalog.text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.timestamptz_le_text,
    LEFTARG = pg_catalog.timestamptz,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamptz_eq_text(pg_catalog.timestamptz, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamptz;
BEGIN
    tmp2 := $2::pg_catalog.timestamptz;
    return ($1 = tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 = $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.timestamptz, pg_catalog.text);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.timestamptz_eq_text,
    LEFTARG = pg_catalog.timestamptz,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamptz_ne_text(pg_catalog.timestamptz, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.timestamptz;
BEGIN
    tmp2 := $2::pg_catalog.timestamptz;
    return ($1 != tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 != $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.timestamptz, pg_catalog.text);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.timestamptz_ne_text,
    LEFTARG = pg_catalog.timestamptz,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.time_gt_text(pg_catalog.time, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.time;
BEGIN
    tmp2 := $2::pg_catalog.time;
    return ($1 > tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 > $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.time, pg_catalog.text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.time_gt_text,
    LEFTARG = pg_catalog.time,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.time_ge_text(pg_catalog.time, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.time;
BEGIN
    tmp2 := $2::pg_catalog.time;
    return ($1 >= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 >= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.time, pg_catalog.text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.time_ge_text,
    LEFTARG = pg_catalog.time,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.time_lt_text(pg_catalog.time, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.time;
BEGIN
    tmp2 := $2::pg_catalog.time;
    return ($1 < tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 < $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.time, pg_catalog.text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.time_lt_text,
    LEFTARG = pg_catalog.time,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.time_le_text(pg_catalog.time, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.time;
BEGIN
    tmp2 := $2::pg_catalog.time;
    return ($1 <= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 <= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.time, pg_catalog.text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.time_le_text,
    LEFTARG = pg_catalog.time,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.time_eq_text(pg_catalog.time, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.time;
BEGIN
    tmp2 := $2::pg_catalog.time;
    return ($1 = tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 = $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.time, pg_catalog.text);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.time_eq_text,
    LEFTARG = pg_catalog.time,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.time_ne_text(pg_catalog.time, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.time;
BEGIN
    tmp2 := $2::pg_catalog.time;
    return ($1 != tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 != $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.time, pg_catalog.text);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.time_ne_text,
    LEFTARG = pg_catalog.time,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.date_gt_text(pg_catalog.date, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.date;
BEGIN
    tmp2 := $2::pg_catalog.date;
    return ($1 > tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 > $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.date, pg_catalog.text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.date_gt_text,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.date_ge_text(pg_catalog.date, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.date;
BEGIN
    tmp2 := $2::pg_catalog.date;
    return ($1 >= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 >= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.date, pg_catalog.text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.date_ge_text,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.date_lt_text(pg_catalog.date, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.date;
BEGIN
    tmp2 := $2::pg_catalog.date;
    return ($1 < tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 < $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.date, pg_catalog.text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.date_lt_text,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.date_le_text(pg_catalog.date, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.date;
BEGIN
    tmp2 := $2::pg_catalog.date;
    return ($1 <= tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 <= $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.date, pg_catalog.text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.date_le_text,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.date_eq_text(pg_catalog.date, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.date;
BEGIN
    tmp2 := $2::pg_catalog.date;
    return ($1 = tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 = $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.date, pg_catalog.text);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.date_eq_text,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.date_ne_text(pg_catalog.date, pg_catalog.text)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.text;
    tmp2 pg_catalog.date;
BEGIN
    tmp2 := $2::pg_catalog.date;
    return ($1 != tmp2);

    EXCEPTION
        WHEN others THEN
            tmp1 := $1::pg_catalog.text;
            return (tmp1 != $2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.date, pg_catalog.text);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.date_ne_text,
    LEFTARG = pg_catalog.date,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.part_list_columns(VARIADIC pg_catalog.any)
RETURNS pg_catalog.text
AS '$libdir/mysm', 'partListColumns'
IMMUTABLE LANGUAGE C;

CREATE OR REPLACE FUNCTION mysql.year(date)
RETURNS integer
AS
$$
    SELECT EXTRACT(YEAR FROM $1)::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.text_gt_timestamp(pg_catalog.text, pg_catalog.timestamp)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamp;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamp;
    return (tmp1 > $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 > tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.text, pg_catalog.timestamp);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.text_gt_timestamp,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamp
);

CREATE OR REPLACE FUNCTION mysql.text_ge_timestamp(pg_catalog.text, pg_catalog.timestamp)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamp;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamp;
    return (tmp1 >= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 >= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.text, pg_catalog.timestamp);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.text_ge_timestamp,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamp
);

CREATE OR REPLACE FUNCTION mysql.text_lt_timestamp(pg_catalog.text, pg_catalog.timestamp)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamp;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamp;
    return (tmp1 < $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 < tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.text, pg_catalog.timestamp);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.text_lt_timestamp,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamp
);

CREATE OR REPLACE FUNCTION mysql.text_le_timestamp(pg_catalog.text, pg_catalog.timestamp)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamp;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamp;
    return (tmp1 <= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 <= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.text, pg_catalog.timestamp);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.text_le_timestamp,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamp
);

CREATE OR REPLACE FUNCTION mysql.text_eq_timestamp(pg_catalog.text, pg_catalog.timestamp)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamp;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamp;
    return (tmp1 = $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 = tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.text, pg_catalog.timestamp);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.text_eq_timestamp,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamp
);

CREATE OR REPLACE FUNCTION mysql.text_ne_timestamp(pg_catalog.text, pg_catalog.timestamp)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamp;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamp;
    return (tmp1 != $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 != tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.text, pg_catalog.timestamp);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.text_ne_timestamp,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamp
);

CREATE OR REPLACE FUNCTION mysql.text_gt_timestamptz(pg_catalog.text, pg_catalog.timestamptz)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamptz;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamptz;
    return (tmp1 > $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 > tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.text, pg_catalog.timestamptz);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.text_gt_timestamptz,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamptz
);

CREATE OR REPLACE FUNCTION mysql.text_ge_timestamptz(pg_catalog.text, pg_catalog.timestamptz)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamptz;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamptz;
    return (tmp1 >= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 >= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.text, pg_catalog.timestamptz);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.text_ge_timestamptz,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamptz
);

CREATE OR REPLACE FUNCTION mysql.text_lt_timestamptz(pg_catalog.text, pg_catalog.timestamptz)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamptz;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamptz;
    return (tmp1 < $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 < tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.text, pg_catalog.timestamptz);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.text_lt_timestamptz,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamptz
);

CREATE OR REPLACE FUNCTION mysql.text_le_timestamptz(pg_catalog.text, pg_catalog.timestamptz)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamptz;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamptz;
    return (tmp1 <= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 <= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.text, pg_catalog.timestamptz);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.text_le_timestamptz,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamptz
);

CREATE OR REPLACE FUNCTION mysql.text_eq_timestamptz(pg_catalog.text, pg_catalog.timestamptz)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamptz;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamptz;
    return (tmp1 = $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 = tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.text, pg_catalog.timestamptz);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.text_eq_timestamptz,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamptz
);

CREATE OR REPLACE FUNCTION mysql.text_ne_timestamptz(pg_catalog.text, pg_catalog.timestamptz)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.timestamptz;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.timestamptz;
    return (tmp1 != $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 != tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.text, pg_catalog.timestamptz);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.text_ne_timestamptz,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.timestamptz
);

CREATE OR REPLACE FUNCTION mysql.text_gt_time(pg_catalog.text, pg_catalog.time)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.time;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.time;
    return (tmp1 > $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 > tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.text, pg_catalog.time);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.text_gt_time,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.time
);

CREATE OR REPLACE FUNCTION mysql.text_ge_time(pg_catalog.text, pg_catalog.time)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.time;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.time;
    return (tmp1 >= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 >= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.text, pg_catalog.time);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.text_ge_time,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.time
);

CREATE OR REPLACE FUNCTION mysql.text_lt_time(pg_catalog.text, pg_catalog.time)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.time;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.time;
    return (tmp1 < $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 < tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.text, pg_catalog.time);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.text_lt_time,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.time
);

CREATE OR REPLACE FUNCTION mysql.text_le_time(pg_catalog.text, pg_catalog.time)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.time;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.time;
    return (tmp1 <= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 <= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.text, pg_catalog.time);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.text_le_time,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.time
);

CREATE OR REPLACE FUNCTION mysql.text_eq_time(pg_catalog.text, pg_catalog.time)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.time;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.time;
    return (tmp1 = $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 = tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.text, pg_catalog.time);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.text_eq_time,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.time
);

CREATE OR REPLACE FUNCTION mysql.text_ne_time(pg_catalog.text, pg_catalog.time)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.time;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.time;
    return (tmp1 != $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 != tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.text, pg_catalog.time);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.text_ne_time,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.time
);

CREATE OR REPLACE FUNCTION mysql.text_gt_date(pg_catalog.text, pg_catalog.date)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.date;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.date;
    return (tmp1 > $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 > tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.text, pg_catalog.date);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.text_gt_date,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.date
);

CREATE OR REPLACE FUNCTION mysql.text_ge_date(pg_catalog.text, pg_catalog.date)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.date;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.date;
    return (tmp1 >= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 >= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.text, pg_catalog.date);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.text_ge_date,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.date
);

CREATE OR REPLACE FUNCTION mysql.text_lt_date(pg_catalog.text, pg_catalog.date)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.date;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.date;
    return (tmp1 < $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 < tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.text, pg_catalog.date);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.text_lt_date,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.date
);

CREATE OR REPLACE FUNCTION mysql.text_le_date(pg_catalog.text, pg_catalog.date)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.date;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.date;
    return (tmp1 <= $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 <= tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.text, pg_catalog.date);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.text_le_date,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.date
);

CREATE OR REPLACE FUNCTION mysql.text_eq_date(pg_catalog.text, pg_catalog.date)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.date;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.date;
    return (tmp1 = $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 = tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.text, pg_catalog.date);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.text_eq_date,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.date
);

CREATE OR REPLACE FUNCTION mysql.text_ne_date(pg_catalog.text, pg_catalog.date)
returns pg_catalog.bool
AS
$$
DECLARE
    tmp1 pg_catalog.date;
    tmp2 pg_catalog.text;
BEGIN
    tmp1 := $1::pg_catalog.date;
    return (tmp1 != $2);

    EXCEPTION
        WHEN others THEN
            tmp2 := $2::pg_catalog.text;
            return ($1 != tmp2);
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!=(pg_catalog.text, pg_catalog.date);
CREATE OPERATOR mysql.!= (
    FUNCTION = mysql.text_ne_date,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.date
);

CREATE OR REPLACE FUNCTION mysql.int4andtext(pg_catalog.int4, text)
RETURNS pg_catalog.int4
AS
$$
BEGIN
    return $1 & mysql.convert_text_to_digit_text_for_mysql($2)::integer;
END;
$$
STRICT
language plpgsql;
DROP OPERATOR IF EXISTS mysql.&(pg_catalog.int4, text);
CREATE OPERATOR mysql.&(
    FUNCTION=mysql.int4andtext,
    LEFTARG=pg_catalog.int4,
    RIGHTARG=text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_gt_text(pg_catalog.timestamp, pg_catalog.text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'mys_timestampGtText'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.>(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.> (
    FUNCTION = mysql.timestamp_gt_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_ge_text(pg_catalog.timestamp, pg_catalog.text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'mys_timestampGeText'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.>=(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.>= (
    FUNCTION = mysql.timestamp_ge_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_lt_text(pg_catalog.timestamp, pg_catalog.text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'mys_timestampLtText'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.<(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.< (
    FUNCTION = mysql.timestamp_lt_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_le_text(pg_catalog.timestamp, pg_catalog.text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'mys_timestampLeText'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.<=(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.<= (
    FUNCTION = mysql.timestamp_le_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.timestamp_eq_text(pg_catalog.timestamp, pg_catalog.text)
returns pg_catalog.bool
AS '$libdir/mysm', 'mys_timestampEqText'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.=(pg_catalog.timestamp, pg_catalog.text);
CREATE OPERATOR mysql.= (
    FUNCTION = mysql.timestamp_eq_text,
    LEFTARG = pg_catalog.timestamp,
    RIGHTARG = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.text_pl_interval(text, pg_catalog.interval)
RETURNS timestamp without time zone
AS '$libdir/mysm', 'mys_textPlInterval'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.+(pg_catalog.text, pg_catalog.interval);
CREATE OPERATOR mysql.+(
    function = mysql.text_pl_interval,
    leftarg = pg_catalog.text,
    rightarg = pg_catalog.interval
);

CREATE OR REPLACE FUNCTION mysql.interval_pl_text(pg_catalog.interval, text)
RETURNS timestamp without time zone
AS '$libdir/mysm', 'mys_intervalPlText'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.+(pg_catalog.interval, pg_catalog.text);
CREATE OPERATOR mysql.+(
    function = mysql.interval_pl_text,
    leftarg = pg_catalog.interval,
    rightarg = pg_catalog.text
);

CREATE OR REPLACE FUNCTION mysql.text_mi_interval(text, pg_catalog.interval)
RETURNS timestamp without time zone
AS '$libdir/mysm', 'mys_textMiInterval'
LANGUAGE C
STRICT
IMMUTABLE;
DROP OPERATOR IF EXISTS mysql.-(pg_catalog.text, pg_catalog.interval);
CREATE OPERATOR mysql.-(
    function = mysql.text_mi_interval,
    leftarg = text,
    rightarg = pg_catalog.interval
);

DROP OPERATOR IF EXISTS mysql.~~(pg_catalog.int8, pg_catalog.text);
DROP FUNCTION IF EXISTS mysql.bigint_like_text(pg_catalog.int8, pg_catalog.text);
CREATE OR REPLACE FUNCTION mysql.bigint_like_text(pg_catalog.int8, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1::pg_catalog.text like $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.~~(pg_catalog.int8, pg_catalog.text);
CREATE OPERATOR mysql.~~ (
    FUNCTION = mysql.bigint_like_text,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.text
);

DROP OPERATOR IF EXISTS mysql.~~(pg_catalog.text, pg_catalog.int8);
DROP FUNCTION IF EXISTS mysql.text_like_bigint(pg_catalog.text, pg_catalog.int8);
CREATE OR REPLACE FUNCTION mysql.text_like_bigint(pg_catalog.text, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 like $2::pg_catalog.text;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.~~(pg_catalog.text, pg_catalog.int8);
CREATE OPERATOR mysql.~~ (
    FUNCTION = mysql.text_like_bigint,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.int8
);

DROP OPERATOR IF EXISTS mysql.!~~(pg_catalog.int8, pg_catalog.text);
DROP FUNCTION IF EXISTS mysql.bigint_not_like_text(pg_catalog.int8, pg_catalog.text);
CREATE OR REPLACE FUNCTION mysql.bigint_not_like_text(pg_catalog.int8, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1::pg_catalog.text not like $2;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!~~(pg_catalog.int8, pg_catalog.text);
CREATE OPERATOR mysql.!~~ (
    FUNCTION = mysql.bigint_not_like_text,
    LEFTARG = pg_catalog.int8,
    RIGHTARG = pg_catalog.text
);

DROP OPERATOR IF EXISTS mysql.!~~(pg_catalog.text, pg_catalog.int8);
DROP FUNCTION IF EXISTS mysql.text_not_like_bigint(pg_catalog.text, pg_catalog.int8);
CREATE OR REPLACE FUNCTION mysql.text_not_like_bigint(pg_catalog.text, pg_catalog.int8)
returns pg_catalog.bool
AS
$$
BEGIN
    return $1 not like $2::pg_catalog.text;
END
$$
language 'plpgsql';
DROP OPERATOR IF EXISTS mysql.!~~(pg_catalog.text, pg_catalog.int8);
CREATE OPERATOR mysql.!~~ (
    FUNCTION = mysql.text_not_like_bigint,
    LEFTARG = pg_catalog.text,
    RIGHTARG = pg_catalog.int8
);


GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mysql TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mys_informa_schema TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA sys TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mys_sys TO public;


CREATE OR REPLACE FUNCTION mysql.convert_text_to_float8(text)
RETURNS float8
AS '$libdir/mysm', 'convertTextToDouble'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.convert_time_to_float8(time)
RETURNS float8
AS '$libdir/mysm', 'convertTimeToDouble'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.convert_date_to_float8(date)
RETURNS float8
AS '$libdir/mysm', 'convertDateToDouble'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.convert_timestamp_to_float8(timestamp)
RETURNS float8
AS '$libdir/mysm', 'convertTimestampToDouble'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.isnull(mysql.smallint)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, -702584691) = -702584691 then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val int)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, -702584691) = -702584691 then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(bigint)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, -702584691) = -702584691 then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(mysql.real)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, -702584691) = -702584691 then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val numeric)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, -702584691) = -702584691 then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val char)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, '-702584691') = '-702584691' then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val varchar)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, '-702584691') = '-702584691' then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val text)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, '-702584691') = '-702584691' then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val date)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    ---if coalesce(val, '1000-02-01') = '1000-02-01' then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val time)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, '00:00:00') = '00:00:00' then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.isnull(val timestamp)
RETURNS int
AS
$$
DECLARE
    ret int;
BEGIN
    --if coalesce(val, '1000-02-01 00:00:01') = '1000-02-01 00:00:01' then
    if $1 is null then
        ret = 1;
    else
        ret = 0;
    end if;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(mysql.tinyint, mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(mysql.smallint, mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(int, int)
RETURNS int
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(bigint, bigint)
RETURNS bigint
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(pg_catalog.bool, pg_catalog.bool)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(text, text)
RETURNS text
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(varchar, varchar)
RETURNS varchar
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(char, char)
RETURNS char
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(float, float)
RETURNS float
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(mysql.double, mysql.double)
RETURNS mysql.double
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(numeric, numeric)
RETURNS numeric
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(time, time)
RETURNS time
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(date, date)
RETURNS date
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(timestamp, timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE or replace FUNCTION mysql.ifnull(p1 pg_catalog.bool, p2 text)
RETURNS text IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 mysql.smallint, p2 text)
RETURNS text IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 int, p2 text)
RETURNS text IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 bigint, p2 text)
RETURNS text IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 numeric, p2 text)
RETURNS numeric IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 date, p2 text)
RETURNS timestamp IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 time, p2 text)
RETURNS timestamp IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 timestamp, p2 text)
RETURNS timestamp IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE or replace FUNCTION mysql.ifnull(p1 timestamptz, p2 text)
RETURNS timestamptz IMMUTABLE AS $$
SELECT coalesce(p1::text, p2);
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION mysql.field(t1 mysql.smallint, VARIADIC arr mysql.smallint[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 int, VARIADIC arr int[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 bigint, VARIADIC arr bigint[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 char, VARIADIC arr char[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 varchar, VARIADIC arr varchar[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 text, VARIADIC arr text[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 date, VARIADIC arr date[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 time, VARIADIC arr time[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.field(t1 timestamp, VARIADIC arr timestamp[])
RETURNS int
AS
$$
DECLARE
    i int;
BEGIN
    for i in 1..array_length(arr, 1) loop
        if t1 = arr[i] then
            return i;
        end if;
    end loop;

    return 0;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.round(integer)
RETURNS integer
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.round(integer, integer)
RETURNS integer
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.round(numeric)
RETURNS integer
AS
$$
BEGIN
    if $1 is not null then
        return $1::integer;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.round(numeric, integer)
RETURNS numeric
AS
$$
BEGIN
    if ($1 is not null) and ($2 is not null) then
        return pg_catalog.round($1, $2);
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.round(text)
RETURNS numeric
AS
$$
BEGIN
    if $1 is not null then
        return pg_catalog.round(mysql.convert_text_to_digit_text_for_mysql($1)::numeric);
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.round(text, integer)
RETURNS numeric
AS
$$
BEGIN
    if ($1 is not null) and ($2 is not null) then

        if 0 < $2 then
            return pg_catalog.round(mysql.convert_text_to_digit_text_for_mysql($1)::numeric, $2);
        elsif $2 = 0 then
            return pg_catalog.round(mysql.convert_text_to_digit_text_for_mysql($1)::numeric);
        else
            return 0;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.ceil_for_mysql(text)
RETURNS bigint
AS '$libdir/mysm', 'ceil_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.floor_for_mysql(text)
RETURNS bigint
AS '$libdir/mysm', 'floor_for_mysql'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.ceil(text)
RETURNS bigint
AS
$$
BEGIN
    if ($1 is not null) then
        raise notice 'mysql.ceil(text) [%]', $1;
        return mysql.ceil_for_mysql($1);
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.ceiling(text)
RETURNS bigint
AS
$$
BEGIN
    if ($1 is not null) then
        raise notice 'mysql.ceiling(text) [%]', $1;
        return mysql.ceil_for_mysql($1);
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.floor(text)
RETURNS bigint
AS
$$
BEGIN
    if ($1 is not null) then
        return mysql.floor_for_mysql($1);
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.mod(mysql.smallint, mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if ($1 is not null) and ($2 is not null) then
        if $2 != 0 then
            return pg_catalog.mod($1, $2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(integer, integer)
RETURNS integer
AS
$$
BEGIN
    if ($1 is not null) and ($2 is not null) then
        if $2 != 0 then
            return pg_catalog.mod($1, $2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(bigint, bigint)
RETURNS bigint
AS
$$
BEGIN
    if ($1 is not null) and ($2 is not null) then
        if $2 != 0 then
            return pg_catalog.mod($1, $2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(text, mysql.smallint)
RETURNS numeric
AS
$$
DECLARE
    tmp1 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        if $2 != 0 then
            tmp1 = mysql.convert_text_to_float8($1);
            return pg_catalog.mod(tmp1, $2::numeric);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(text, int)
RETURNS numeric
AS
$$
DECLARE
    tmp1 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        if $2 != 0 then
            tmp1 = mysql.convert_text_to_float8($1);
            return pg_catalog.mod(tmp1, $2::numeric);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE PLPGSQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(text, bigint)
RETURNS numeric
AS
$$
DECLARE
    tmp1 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        if $2 != 0 then
            tmp1 = mysql.convert_text_to_float8($1);
            return pg_catalog.mod(tmp1, $2::numeric);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(mysql.smallint, text)
RETURNS numeric
AS
$$
DECLARE
    tmp2 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        tmp2 = mysql.convert_text_to_float8($2);
        if tmp2 != 0 then
            return pg_catalog.mod($1::numeric, tmp2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(int, text)
RETURNS numeric
AS
$$
DECLARE
    tmp2 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        tmp2 = mysql.convert_text_to_float8($2);
        if tmp2 != 0 then
            return pg_catalog.mod($1::numeric, tmp2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(bigint, text)
RETURNS numeric
AS
$$
DECLARE
    tmp2 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        tmp2 = mysql.convert_text_to_float8($2);
        if tmp2 != 0 then
            return pg_catalog.mod($1::numeric, tmp2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(text, numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp1 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        if $2 != 0 then
            tmp1 = mysql.convert_text_to_float8($1);
            return pg_catalog.mod(tmp1, $2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(numeric, text)
RETURNS numeric
AS
$$
DECLARE
    tmp2 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        tmp2 = mysql.convert_text_to_float8($2);
        if tmp2 != 0 then
            return pg_catalog.mod($1, tmp2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.mod(text, text)
RETURNS numeric
AS
$$
DECLARE
    tmp1 numeric;
    tmp2 numeric;
BEGIN
    if ($1 is not null) and ($2 is not null) then
        tmp1 = mysql.convert_text_to_float8($1);
        tmp2 = mysql.convert_text_to_float8($2);
        if tmp2 != 0 then
            return pg_catalog.mod(tmp1, tmp2);
        else
            return null;
        end if;
    else
        return null;
    end if;
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION mysql.sleep(in seconds numeric)
RETURNS varchar
AS
$$
DECLARE
    tmp_ret varchar;
BEGIN
    tmp_ret = (select pg_sleep(seconds));
    return '0';
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.timestampadd(text, integer, timestamp without time zone)
RETURNS timestamp without time zone
AS
$$
    SELECT $3 + ($2 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $1)::pg_catalog.interval
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.timestampdiff(unit text, ts1 timestamp, ts2 timestamp)
RETURNS bigint
AS '$libdir/mysm', 'timestampdiff'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.utc_date()
RETURNS date
AS
$$
    SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.utc_time()
RETURNS time(0)
AS
$$
    SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::time(0)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.utc_timestamp()
RETURNS timestamp(0)
AS
$$
    SELECT (CURRENT_TIMESTAMP::pg_catalog.timestamptz AT TIME ZONE 'UTC')::timestamp(0)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_format(timestamptz, text)
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
                WHEN n =# 'a' THEN pg_catalog.to_char($1, 'Dy')
                WHEN n =# 'b' THEN pg_catalog.to_char($1, 'Mon')
                WHEN n =# 'c' THEN pg_catalog.to_char($1, 'FMMM')
                WHEN n =# 'D' THEN pg_catalog.to_char($1, 'FMDDth')
                WHEN n =# 'd' THEN pg_catalog.to_char($1, 'DD')
                WHEN n =# 'e' THEN pg_catalog.to_char($1, 'FMDD')
                WHEN n =# 'f' THEN pg_catalog.to_char($1, 'US')
                WHEN n =# 'H' THEN pg_catalog.to_char($1, 'HH24')
                WHEN n =# 'h' THEN pg_catalog.to_char($1, 'HH12')
                WHEN n =# 'I' THEN pg_catalog.to_char($1, 'HH12')
                WHEN n =# 'i' THEN pg_catalog.to_char($1, 'MI')
                WHEN n =# 'j' THEN pg_catalog.to_char($1, 'DDD')
                WHEN n =# 'k' THEN pg_catalog.to_char($1, 'FMHH24')
                WHEN n =# 'l' THEN pg_catalog.to_char($1, 'FMHH12')
                WHEN n =# 'M' THEN pg_catalog.to_char($1, 'FMMonth')
                WHEN n =# 'm' THEN pg_catalog.to_char($1, 'MM')
                WHEN n =# 'p' THEN pg_catalog.to_char($1, 'AM')
                WHEN n =# 'r' THEN pg_catalog.to_char($1, 'HH12:MI:SS AM')
                WHEN n =# 'S' THEN pg_catalog.to_char($1, 'SS')
                WHEN n =# 's' THEN pg_catalog.to_char($1, 'SS')
                WHEN n =# 'T' THEN pg_catalog.to_char($1, 'HH24:MI:SS')
                WHEN n =# 'U' THEN pg_catalog.lpad(week($1::date, 0)::text, 2, '0')
                WHEN n =# 'u' THEN pg_catalog.lpad(week($1::date, 1)::text, 2, '0')
                WHEN n =# 'V' THEN pg_catalog.lpad(week($1::date, 2)::text, 2, '0')
                WHEN n =# 'v' THEN pg_catalog.lpad(week($1::date, 3)::text, 2, '0')
                WHEN n =# 'W' THEN pg_catalog.to_char($1, 'FMDay')
                WHEN n =# 'w' THEN EXTRACT(DOW FROM $1)::text
                WHEN n =# 'X' THEN pg_catalog.lpad(((_calc_week($1::date, _week_mode(2)))[2])::text, 4, '0')
                WHEN n =# 'x' THEN pg_catalog.lpad(((_calc_week($1::date, _week_mode(3)))[2])::text, 4, '0')
                WHEN n =# 'Y' THEN pg_catalog.to_char($1, 'YYYY')
                WHEN n =# 'y' THEN pg_catalog.to_char($1, 'YY')
                WHEN n =# '%' THEN pg_catalog.to_char($1, '%')
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

-- TIME_FORMAT()
CREATE OR REPLACE FUNCTION mysql.time_format(pg_catalog.interval, text)
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
        -- Look at current character
        c := substring($2 FROM i FOR 1);
        -- If it's a '%' and not the last character then process it as a placeholder
        IF c = '%' AND i != len THEN
            n := (substring($2 FROM (i + 1) FOR 1))::character;
            SELECT INTO res CASE
            WHEN n =# 'a' THEN '0'
            WHEN n =# 'b' THEN '0'
            WHEN n =# 'c' THEN '0'
            WHEN n =# 'D' THEN '0'
            WHEN n =# 'd' THEN '0'
            WHEN n =# 'e' THEN '0'
            WHEN n =# 'f' THEN pg_catalog.to_char($1, 'US')
            WHEN n =# 'H' THEN pg_catalog.to_char($1, 'HH24')
            WHEN n =# 'h' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'I' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'i' THEN pg_catalog.to_char($1, 'MI')
            WHEN n =# 'j' THEN '0'
            WHEN n =# 'k' THEN pg_catalog.to_char($1, 'FMHH24')
            WHEN n =# 'l' THEN (pg_catalog.to_char($1, 'FMHH12')::integer % 12)::text
            WHEN n =# 'M' THEN '0'
            WHEN n =# 'm' THEN '0'
            WHEN n =# 'p' THEN pg_catalog.to_char($1, 'AM')
            WHEN n =# 'r' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
                operator(pg_catalog.||)
                pg_catalog.to_char($1, ':MI:SS ')
                operator(pg_catalog.||)
                CASE WHEN pg_catalog.to_char($1, 'FMHH24')::integer <= 11 THEN 'AM' ELSE 'PM' END
            WHEN n =# 'S' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 's' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 'T' THEN pg_catalog.to_char($1, 'HH24:MI:SS')
            WHEN n =# 'U' THEN '0'
            WHEN n =# 'u' THEN '0'
            WHEN n =# 'V' THEN '0'
            WHEN n =# 'v' THEN '0'
            WHEN n =# 'W' THEN '0'
            WHEN n =# 'w' THEN '0'
            WHEN n =# 'X' THEN '0'
            WHEN n =# 'x' THEN '0'
            WHEN n =# 'Y' THEN '0'
            WHEN n =# 'y' THEN '0'
            WHEN n =# '%' THEN pg_catalog.to_char($1, '%')
            ELSE NULL
            END;
            if res is not null then
                temp := temp operator(pg_catalog.||) res;
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            -- Otherwise just append the character to the string
            temp = temp operator(pg_catalog.||) c;
            i := i + 1;
        END IF;
    END LOOP;
    RETURN temp;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.time_format(timestamp, text)
RETURNS text AS $$
select mysql.time_format($1::time::pg_catalog.interval, $2)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.time_format(text, text)
RETURNS text AS $$
select mysql.time_format($1::pg_catalog.interval, $2)
$$ IMMUTABLE STRICT LANGUAGE SQL;

-- STR_TO_DATE()
-- Note: Doesn't handle weeks of years yet and will return different results
-- to MySQL if you pass in an invalid timestamp
CREATE OR REPLACE FUNCTION mysql.str_to_date(text, text)
RETURNS timestamp without time zone
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
            WHEN n =# 'a' THEN 'Dy'
            WHEN n =# 'b' THEN 'Mon'
            WHEN n =# 'c' THEN 'FMMM'
            WHEN n =# 'D' THEN 'FMDDth'
            WHEN n =# 'd' THEN 'DD'
            WHEN n =# 'e' THEN 'FMDD'
            WHEN n =# 'f' THEN 'US'
            WHEN n =# 'H' THEN 'HH24'
            WHEN n =# 'h' THEN 'HH12'
            WHEN n =# 'I' THEN 'HH12'
            WHEN n =# 'i' THEN 'MI'
            WHEN n =# 'j' THEN 'DDD'
            WHEN n =# 'k' THEN 'FMHH24'
            WHEN n =# 'l' THEN 'FMHH12'
            WHEN n =# 'M' THEN 'FMMonth'
            WHEN n =# 'm' THEN 'MM'
            WHEN n =# 'p' THEN 'AM'
            WHEN n =# 'r' THEN 'HH12:MI:SS AM'
            WHEN n =# 'S' THEN 'SS'
            WHEN n =# 's' THEN 'SS'
            WHEN n =# 'T' THEN 'HH24:MI:SS'
            WHEN n =# 'U' THEN '?'
            WHEN n =# 'u' THEN '?'
            WHEN n =# 'V' THEN '?'
            WHEN n =# 'v' THEN '?'
            WHEN n =# 'W' THEN 'FMDay'
            WHEN n =# 'w' THEN '?'
            WHEN n =# 'X' THEN '?'
            WHEN n =# 'x' THEN '?'
            WHEN n =# 'Y' THEN 'YYYY'
            WHEN n =# 'y' THEN 'YY'
            WHEN n =# '%' THEN '%'
            ELSE NULL
            END;
            if res is not null then
                temp := temp operator(pg_catalog.||) res;
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            temp = temp operator(pg_catalog.||) c;
            i := i + 1;
        END IF;
    END LOOP;

    RETURN pg_catalog.to_timestamp($1, temp)::timestamp without time zone;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.mid(str text, pos integer, len integer)
RETURNS text
AS
$$
select mysql.substring(str, pos, len)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.now()
RETURNS timestamp
AS
$$
    SELECT pg_catalog.now()::timestamp(0)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.now(in prec int)
RETURNS timestamp
AS
$$
DECLARE
    tmp timestamp;
    ret timestamp;
BEGIN
    tmp = (select pg_catalog.now());
    if prec = 0 then
        ret = tmp::timestamp(0);
    elsif prec = 1 then
        ret = tmp::timestamp(1);
    elsif prec = 2 then
        ret = tmp::timestamp(2);
    elsif prec = 3 then
        ret = tmp::timestamp(3);
    elsif prec = 4 then
        ret = tmp::timestamp(4);
    elsif prec = 5 then
        ret = tmp::timestamp(5);
    elsif prec = 6 then
        ret = tmp::timestamp(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''now''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.sysdate()
RETURNS timestamp
AS
$$
    SELECT pg_catalog.clock_timestamp()::timestamp(0)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.sysdate(in prec int)
RETURNS timestamp
AS
$$
DECLARE
    tmp timestamp;
    ret timestamp;
BEGIN
    tmp = (select pg_catalog.clock_timestamp());
    if prec = 0 then
        ret = tmp::timestamp(0);
    elsif prec = 1 then
        ret = tmp::timestamp(1);
    elsif prec = 2 then
        ret = tmp::timestamp(2);
    elsif prec = 3 then
        ret = tmp::timestamp(3);
    elsif prec = 4 then
        ret = tmp::timestamp(4);
    elsif prec = 5 then
        ret = tmp::timestamp(5);
    elsif prec = 6 then
        ret = tmp::timestamp(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''sysdate''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.curdate()
RETURNS date
AS
$$
    SELECT CURRENT_DATE
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.curdate_add(integer)
RETURNS integer
AS
$$
DECLARE
    tmp text;
BEGIN
    tmp = (select current_date);
    tmp = pg_catalog.replace(tmp, '-', '');
    tmp = pg_catalog.replace(tmp, '-', '');
    return (tmp::integer + $1);
END
$$
language 'plpgsql';

-- 这里的操作符还可以是 / * 等等，操作数也可以是浮点数
-- 考虑到业务价值极小，暂时不实现
CREATE OR REPLACE FUNCTION mysql.curdate_sub(integer)
RETURNS integer
AS
$$
DECLARE
    tmp text;
BEGIN
    tmp = (select current_date);
    tmp = pg_catalog.replace(tmp, '-', '');
    tmp = pg_catalog.replace(tmp, '-', '');
    return (tmp::integer - $1);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.curtime()
RETURNS time
AS
$$
   SELECT CURRENT_TIME(0);
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.curtime(in prec int)
RETURNS time
AS
$$
DECLARE
    ret time(6);
BEGIN
    if prec = 0 then
        ret = (select current_time(0));
    elsif prec = 1 then
        ret = (select current_time(1));
    elsif prec = 2 then
        ret = (select current_time(2));
    elsif prec = 3 then
        ret = (select current_time(3));
    elsif prec = 4 then
        ret = (select current_time(4));
    elsif prec = 5 then
        ret = (select current_time(5));
    elsif prec = 6 then
        ret = (select current_time(6));
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''curtime''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql._date_padding(text)
RETURNS text
AS
$$
DECLARE
    ori_str text := $1;
    ori_len int := char_length($1);
    rt_str text;
BEGIN
    if ori_len = 3 then
        rt_str := concat('20000', ori_str);
    elsif ori_len = 4 then
        rt_str := concat('2000', ori_str);
    elsif ori_len = 5 then
        rt_str := concat('200', ori_str);
    else
        rt_str := ori_str;
    end if;

    return rt_str;
END
$$
LANGUAGE 'plpgsql';

-- 传入的参数应该是date或datetime格式(可能是全数字)
CREATE OR REPLACE FUNCTION mysql._convert_date_format_to_halo(text)
RETURNS text
AS
$$
DECLARE
    ori_str text := $1;
    ori_len int;
    ori_len_before_point int;
    fin_str text;
    fin_len int;
    tm_date text;
    tm_time text;
    single_point_index int;
BEGIN
    ori_len := char_length(ori_str);

    if position('-' in ori_str) = 0 and position('/' in ori_str) = 0 and position(':' in ori_str) = 0 and position('..' in ori_str) = 0 then
        single_point_index := position('.' in ori_str);
        if single_point_index = 0 then
            ori_len_before_point := ori_len;
            if ori_len_before_point <= 8 then
                fin_str := mysql._date_padding(ori_str);
            else
                tm_date := mysql._date_padding(substring(ori_str, 1, ori_len - 6));
                tm_time := substring(ori_str, ori_len - 6 + 1);
                fin_str := concat(tm_date, ' ', tm_time);
            end if;
        else
            ori_len_before_point := single_point_index - 1;
            if ori_len_before_point <= 8 then
                fin_str := mysql._date_padding(substring(ori_str, 1, ori_len_before_point));
            else
                tm_date := mysql._date_padding(substring(ori_str, 1, ori_len_before_point - 6));
                tm_time := substring(ori_str, ori_len_before_point - 6 + 1);
                fin_str := concat(tm_date, ' ', tm_time);
            end if;
        end if;
    else
        fin_str := ori_str;
    end if;

    fin_len := char_length(fin_str);
    if position('.' in fin_str) = fin_len then
        fin_str := substring(fin_str, 1, fin_len-1);
    end if;

    RETURN fin_str;
END
$$
VOLATILE LANGUAGE 'plpgsql';

---- 存在时区问题：Mysql从'1970-01-01 00:00:00' UTC开始计算
CREATE OR REPLACE FUNCTION mysql.unix_timestamp()
RETURNS bigint AS $$
    SELECT (EXTRACT(EPOCH FROM LOCALTIMESTAMP) - 28800)::bigint
$$ VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(timestamp)
RETURNS decimal AS $$
  SELECT EXTRACT(EPOCH FROM $1)-28800
$$ VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(date)
RETURNS bigint AS $$
  SELECT (EXTRACT(EPOCH FROM $1)-28800)::bigint
$$ VOLATILE LANGUAGE SQL;

---- Mysql还支持输入数字(YYMMDD, YYMMDDhhmmss, YYYYMMDD, or YYYYMMDDhhmmss类型)
CREATE OR REPLACE FUNCTION mysql.unix_timestamp(text)
RETURNS decimal
AS
$$
DECLARE
    fin_str text;
    rt decimal;
BEGIN
    fin_str := mysql._convert_date_format_to_halo($1::text);
    rt := extract(epoch from fin_str::timestamp)-28800;

    RETURN rt;
END
$$
VOLATILE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(numeric)
RETURNS decimal
AS
$$
    SELECT mysql.unix_timestamp($1::text)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(bigint)
RETURNS bigint
AS
$$
    SELECT mysql.unix_timestamp($1::text)::bigint
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(integer)
RETURNS bigint
AS
$$
    SELECT mysql.unix_timestamp($1::text)::bigint
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.from_unixtime(float)
RETURNS timestamp AS $$
  SELECT pg_catalog.to_timestamp($1)::timestamp
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.from_unixtime(float, text)
RETURNS text AS $$
  SELECT date_format(from_unixtime($1), $2)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.makedate(integer, integer)
RETURNS date
AS
$$
    select
        CASE WHEN $2 > 0 THEN
            (($1 operator(pg_catalog.||) '-01-01')::date + ($2 - 1) * '1 day'::pg_catalog.interval)::date
        ELSE
            NULL
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.maketime(integer, integer, integer)
RETURNS pg_catalog.interval
AS
$$
    select ($1 operator(pg_catalog.||) ':' operator(pg_catalog.||) $2 operator(pg_catalog.||) ':' operator(pg_catalog.||) $3)::pg_catalog.interval
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_tz(timestamp, text, text)
RETURNS timestamp
AS
$$
    SELECT
        CASE WHEN POSITION(':' IN $3) = 0 THEN
            ($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp with time zone AT TIME ZONE $3
        ELSE
            ($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp with time zone AT TIME ZONE $3::pg_catalog.interval
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_tz(text, text, text)
RETURNS timestamp
AS
$$
BEGIN
    return mysql.convert_tz($1::timestamp, $2, $3);
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.adddate(timestamp, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT ($1 + $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(timestamp, integer)
RETURNS timestamp
AS
$$
    SELECT $1 + ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

-- adddate('2023-06-09'::date, interval 1 second)返回结果应为timestamp
CREATE OR REPLACE FUNCTION mysql.adddate(date, pg_catalog.interval)
RETURNS date
AS
$$
    SELECT ($1 + $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(date, integer)
RETURNS date
AS
$$
    SELECT $1 + ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_date_format_to_halo($1)::timestamp + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(text, integer)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_date_format_to_halo($1)::timestamp + ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(numeric, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql.adddate($1::text, $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(numeric, integer)
RETURNS timestamp
AS
$$
    SELECT mysql.adddate($1::text, $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_add(timestamp, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1 + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

-- date_add('2023-06-09'::date, interval 1 second)返回结果应为timestamp
CREATE OR REPLACE FUNCTION mysql.date_add(date, pg_catalog.interval)
RETURNS date
AS
$$
    SELECT $1 + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_add(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    select mysql._convert_date_format_to_halo($1)::timestamp + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_add(numeric, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql.date_add($1::text, $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_sub(timestamp, pg_catalog.interval)
RETURNS timestamp AS $$
  SELECT $1 - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

-- date_sub('2023-06-09'::date, interval 1 second)返回结果应为timestamp
CREATE OR REPLACE FUNCTION mysql.date_sub(date, pg_catalog.interval)
RETURNS date AS $$
  SELECT $1 - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_sub(text, pg_catalog.interval)
RETURNS timestamp AS $$
  SELECT mysql._convert_date_format_to_halo($1)::timestamp - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_sub(numeric, pg_catalog.interval)
RETURNS timestamp AS $$
  SELECT mysql.date_sub($1::text, $2)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(timestamp, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1 - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(date, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1 - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_date_format_to_halo($1)::timestamp - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(numeric, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql.subdate($1::text, $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(timestamp, integer)
RETURNS timestamp
AS
$$
    SELECT $1 - ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(date, integer)
RETURNS date
AS
$$
    SELECT $1 - ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(text, integer)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_date_format_to_halo($1)::timestamp - ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(numeric, integer)
RETURNS timestamp
AS
$$
    SELECT mysql.subdate($1::text, $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(date, date)
RETURNS integer AS $$
    SELECT $1 - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(timestamp, timestamp)
RETURNS integer AS $$
    SELECT pg_catalog.DATE($1) - pg_catalog.DATE($2)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(text, text)
RETURNS integer AS $$
    SELECT pg_catalog.DATE(mysql._convert_date_format_to_halo($1)) - pg_catalog.DATE(mysql._convert_date_format_to_halo($2))
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(numeric, numeric)
RETURNS integer AS $$
    SELECT mysql.datediff($1::text, $2::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.timediff(text, text)
RETURNS pg_catalog.interval
AS
$$
BEGIN
    return (select $1::timestamp - $2::timestamp);
EXCEPTION
    WHEN others THEN
        return (select $1::time - $2::time);
END
$$
VOLATILE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.timediff(time, time)
RETURNS pg_catalog.interval
AS $$
    SELECT $1 - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.timediff(timestamp, timestamp)
RETURNS pg_catalog.interval
AS $$
    SELECT $1 - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.addtime(timestamp, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1 + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.addtime(time, pg_catalog.interval)
RETURNS time
AS
$$
    SELECT $1 + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

-- '2023-06-13 12:43:56'不应该返回time
CREATE OR REPLACE FUNCTION mysql.addtime(text, pg_catalog.interval)
RETURNS time
AS
$$
    SELECT $1::time + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_to_time_format(text)
RETURNS pg_catalog.interval
AS
$$
DECLARE
    tmp text;
    len int;
    colon_index int;
    pot_index int;
    c char;
    i int;
BEGIN
    tmp = $1;
    len = pg_catalog.length(tmp);
    colon_index = position(':' in tmp);
    pot_index = position('.' in tmp);

    if 0 < colon_index then
        return $1::pg_catalog.interval;
    else
        if pot_index = 0 then
            i = len;
        else
            i = pot_index - 1;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                i = i - 2;
            else
                return null;
            end if;
        elsif i = 2 then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                return $1::pg_catalog.interval;
            else
                return null;
            end if;
        else
            return $1::pg_catalog.interval;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        elsif 2 = i then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                tmp = '00:' operator(pg_catalog.||) tmp;
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        else
            tmp = '00:0' operator(pg_catalog.||) tmp;
            return tmp::pg_catalog.interval;
        end if;
    end if;
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.subtime(timestamp, text)
RETURNS timestamp
AS
$$
    SELECT $1 - mysql.convert_to_time_format($2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subtime(time, text)
RETURNS time
AS
$$
    SELECT $1 - mysql.convert_to_time_format($2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subtime(text, text)
RETURNS time
AS
$$
    SELECT $1::time - mysql.convert_to_time_format($2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.year(timestamp)
RETURNS integer
AS $$
    SELECT EXTRACT(YEAR FROM DATE($1))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.year(text)
RETURNS integer
AS $$
    SELECT EXTRACT(YEAR FROM DATE(mysql._convert_date_format_to_halo($1)))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.year(numeric)
RETURNS integer
AS $$
    SELECT mysql.year($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.month(timestamp)
RETURNS integer AS $$
  SELECT EXTRACT(MONTH FROM DATE($1))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.month(text)
RETURNS integer
AS $$
    SELECT EXTRACT(MONTH FROM DATE(mysql._convert_date_format_to_halo($1)))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.month(numeric)
RETURNS integer
AS $$
    SELECT mysql.month($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.monthname(timestamp)
RETURNS text AS $$
  SELECT pg_catalog.to_char($1, 'FMMonth')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.monthname(text)
RETURNS text
AS $$
    SELECT pg_catalog.to_char(mysql._convert_date_format_to_halo($1)::timestamp, 'FMMonth')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.monthname(numeric)
RETURNS text
AS $$
    SELECT mysql.monthname($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.day(timestamp)
RETURNS integer AS $$
  SELECT EXTRACT(DAY FROM DATE($1))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.day(text)
RETURNS integer
AS $$
    SELECT EXTRACT(DAY FROM DATE(mysql._convert_date_format_to_halo($1)))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.day(numeric)
RETURNS integer
AS $$
    SELECT mysql.day($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayname(timestamp)
RETURNS text AS $$
  SELECT pg_catalog.to_char($1, 'FMDay')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayname(text)
RETURNS text
AS $$
    SELECT pg_catalog.to_char(mysql._convert_date_format_to_halo($1)::timestamp, 'FMDay')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayname(numeric)
RETURNS text
AS $$
    SELECT mysql.dayname($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

---- DAYOFMONTH()
CREATE OR REPLACE FUNCTION mysql.dayofmonth(timestamp)
RETURNS integer AS $$
  SELECT EXTRACT(DAY FROM DATE($1))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofmonth(text)
RETURNS integer AS $$
  SELECT EXTRACT(DAY FROM DATE(mysql._convert_date_format_to_halo($1)))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofmonth(numeric)
RETURNS integer AS $$
  SELECT mysql.dayofmonth($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

---- DAYOFWEEK()
CREATE OR REPLACE FUNCTION mysql.dayofweek(timestamp)
RETURNS integer AS $$
  SELECT EXTRACT(DOW FROM DATE($1))::integer + 1
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofweek(text)
RETURNS integer AS $$
  SELECT EXTRACT(DOW FROM DATE(mysql._convert_date_format_to_halo($1)))::integer + 1
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofweek(numeric)
RETURNS integer AS $$
  SELECT mysql.dayofweek($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofyear(timestamp)
RETURNS integer AS $$
  SELECT EXTRACT(DOY FROM DATE($1))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofyear(text)
RETURNS integer AS $$
  SELECT EXTRACT(DOY FROM DATE(mysql._convert_date_format_to_halo($1)))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofyear(numeric)
RETURNS integer AS $$
  SELECT mysql.dayofyear($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.last_day(date)
RETURNS date
AS
$$
    SELECT CASE WHEN EXTRACT(MONTH FROM $1) = 12 THEN
                (((extract(year from $1) + 1) operator(pg_catalog.||) '-01-01')::date - '1 day'::pg_catalog.interval)::date
           ELSE
                ((extract(year from $1) operator(pg_catalog.||) '-' operator(pg_catalog.||) (extract(month from $1) + 1) operator(pg_catalog.||) '-01')::date - '1 day'::pg_catalog.interval)::date
           END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.last_day(timestamp)
RETURNS date
AS
$$
DECLARE
    dt date;
BEGIN
    dt = $1::date;
    return mysql.last_day(dt);
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.last_day(timestamptz)
RETURNS date
AS
$$
DECLARE
    dt date;
BEGIN
    dt = $1::date;
    return mysql.last_day(dt);
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.last_day(text)
RETURNS date
AS
$$
DECLARE
    dt date;
BEGIN
    dt = $1::date;
    return mysql.last_day(dt);
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql._week_mode(mode integer)
RETURNS integer AS $$
  DECLARE
    _WEEK_MONDAY_FIRST  CONSTANT integer := 1;
    _WEEK_FIRST_WEEKDAY CONSTANT integer := 4;
    week_format integer := mode & 7;
  BEGIN
    IF (week_format & _WEEK_MONDAY_FIRST) = 0 THEN
      week_format := week_format # _WEEK_FIRST_WEEKDAY;
    END IF;

    RETURN week_format;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql._calc_weekday(qdate date, sundayfirst pg_catalog.bool)
RETURNS integer AS $$
  BEGIN
    RETURN (EXTRACT(DOW FROM qdate)::integer + CASE WHEN sundayfirst THEN 0 ELSE 6 END) % 7;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql._calc_days_in_year(integer)
RETURNS integer AS $$
  BEGIN
    IF ($1 & 3) = 0 AND (($1 % 100) <> 0 OR ($1 % 400) = 0 AND $1 <> 0) THEN
      RETURN 366;
    ELSE
      RETURN 365;
    END IF;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql._calc_week(qdate date, behavior integer)
RETURNS integer[] AS $$
  DECLARE
    _WEEK_MONDAY_FIRST  CONSTANT integer := 1;
    _WEEK_YEAR          CONSTANT integer := 2;
    _WEEK_FIRST_WEEKDAY CONSTANT integer := 4;
    qyear         integer := EXTRACT(YEAR FROM qdate);
    qmonth        integer := EXTRACT(MONTH FROM qdate);
    qday          integer := EXTRACT(DAY FROM qdate);
    daynr         integer := EXTRACT(DOY FROM qdate);
    yday1         date    := pg_catalog.date_trunc('year', qdate);
    first_daynr   integer := 1;
    monday_first  pg_catalog.bool := (behavior & _WEEK_MONDAY_FIRST) <> 0;
    week_year     pg_catalog.bool := (behavior & _WEEK_YEAR) <> 0;
    first_weekday pg_catalog.bool := (behavior & _WEEK_FIRST_WEEKDAY) <> 0;
    weekday       integer := _calc_weekday(yday1, NOT monday_first);
    days          integer;
  BEGIN
    IF qmonth = 1 AND qday <= 7 - weekday THEN
      IF (NOT week_year) AND ((first_weekday AND weekday <> 0) OR (NOT first_weekday AND weekday >= 4)) THEN
        RETURN array[0, qyear];
      END IF;

      week_year := true;
      qyear := qyear - 1;
      days := _calc_days_in_year(qyear);
      first_daynr := first_daynr - days;
      weekday := (weekday + 53 * 7 - days) % 7;
    END IF;

    IF (first_weekday AND weekday <> 0) OR (NOT first_weekday AND weekday >= 4) THEN
      days := daynr - (first_daynr + (7 - weekday));
    ELSE
      days := daynr - (first_daynr - weekday);
    END IF;

    IF week_year AND days >= 52 * 7 THEN
      weekday := (weekday + _calc_days_in_year(qyear)) % 7;
      IF (NOT first_weekday AND weekday < 4) OR (first_weekday AND weekday = 0) THEN
	qyear := qyear + 1;
        RETURN array[1, qyear];
      END IF;
    END IF;

    RETURN array[days / 7 + 1, qyear];
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.week(timestamp, integer)
RETURNS integer AS $$
  SELECT (_calc_week(DATE($1), _week_mode($2)))[1];
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.week(timestamp)
RETURNS integer AS $$
  SELECT week($1, 0);
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.week(text, integer)
RETURNS integer AS $$
  SELECT (_calc_week(DATE(mysql._convert_date_format_to_halo($1)), _week_mode($2)))[1];
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.week(text)
RETURNS integer AS $$
  SELECT mysql.week($1, 0);
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.week(numeric, integer)
RETURNS integer AS $$
  SELECT (_calc_week(DATE(mysql._convert_date_format_to_halo($1::text)), _week_mode($2)))[1];
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.week(numeric)
RETURNS integer AS $$
  SELECT mysql.week($1, 0);
$$ IMMUTABLE STRICT LANGUAGE SQL;

---- WEEKOFYEAR()
CREATE OR REPLACE FUNCTION mysql.weekofyear(timestamp)
RETURNS integer AS $$
  SELECT week($1, 3);
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.weekofyear(text)
RETURNS integer AS $$
  SELECT week($1, 3);
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.weekofyear(numeric)
RETURNS integer AS $$
  SELECT week($1, 3);
$$ IMMUTABLE STRICT LANGUAGE SQL;

---- YEARWEEK()
CREATE OR REPLACE FUNCTION mysql.yearweek(qdate timestamp, mode integer)
RETURNS integer AS $$
  DECLARE
    _WEEK_YEAR CONSTANT integer := 2;
    a integer[] := _calc_week(DATE(qdate), _week_mode(mode | _WEEK_YEAR));
    week integer := a[1];
    _year integer := a[2];
  BEGIN
    RETURN week + _year * 100;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.yearweek(timestamp)
RETURNS integer AS $$
  SELECT yearweek($1, 0);
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.yearweek(qdate text, mode integer)
RETURNS integer AS $$
  DECLARE
    _WEEK_YEAR CONSTANT integer := 2;
    a integer[] := _calc_week(DATE(mysql._convert_date_format_to_halo(qdate)), _week_mode(mode | _WEEK_YEAR));
    week integer := a[1];
    _year integer := a[2];
  BEGIN
    RETURN week + _year * 100;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.yearweek(text)
RETURNS integer AS $$
  SELECT yearweek($1, 0);
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.yearweek(qdate numeric, mode integer)
RETURNS integer AS $$
  DECLARE
    _WEEK_YEAR CONSTANT integer := 2;
    a integer[] := _calc_week(DATE(mysql._convert_date_format_to_halo(qdate::text)), _week_mode(mode | _WEEK_YEAR));
    week integer := a[1];
    _year integer := a[2];
  BEGIN
    RETURN week + _year * 100;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.yearweek(numeric)
RETURNS integer AS $$
  SELECT yearweek($1, 0);
$$ IMMUTABLE STRICT LANGUAGE SQL;
--
---- WEEKDAY()
CREATE OR REPLACE FUNCTION mysql.weekday(timestamp)
RETURNS integer AS $$
  SELECT CASE
    WHEN EXTRACT(DOW FROM $1)::integer = 0 THEN
      6
    ELSE
      EXTRACT(DOW FROM $1)::integer - 1
    END
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.weekday(text)
RETURNS integer AS $$
  SELECT CASE
    WHEN EXTRACT(DOW FROM DATE(mysql._convert_date_format_to_halo($1)))::integer = 0 THEN
      6
    ELSE
      EXTRACT(DOW FROM DATE(mysql._convert_date_format_to_halo($1)))::integer - 1
    END
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.weekday(numeric)
RETURNS integer AS $$
    SELECT mysql.weekday($1::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.hour(time)
RETURNS integer
AS
$$
    select (extract(hour from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.hour(timestamp)
RETURNS integer
AS
$$
    select (extract(hour from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.hour(text)
RETURNS integer
AS
$$
    select (extract(hour from $1::time))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.minute(time)
RETURNS integer
AS
$$
    select (extract(minute from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.minute(timestamp)
RETURNS integer
AS
$$
    select (extract(minute from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.minute(text)
RETURNS integer
AS
$$
    select (extract(minute from $1::time))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.second(time)
RETURNS integer
AS
$$
    select (extract(second from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.second(timestamp)
RETURNS integer
AS
$$
    select (extract(second from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.second(text)
RETURNS integer
AS
$$
    select (extract(second from $1::time))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.microsecond(time)
RETURNS integer
AS
$$
DECLARE
    misec integer;
    sec integer;
    ret integer;
BEGIN
    misec = (select (extract(microsecond from $1))::integer);
    sec = (select (extract(second from $1))::integer);
    ret = misec - sec * 1000000;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.microsecond(timestamp)
RETURNS integer
AS
$$
DECLARE
    misec integer;
    sec integer;
    ret integer;
BEGIN
    misec = (select (extract(microsecond from $1))::integer);
    sec = (select (extract(second from $1))::integer);
    ret = misec - sec * 1000000;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.microsecond(text)
RETURNS integer
AS
$$
DECLARE
    misec integer;
    sec integer;
    ret integer;
BEGIN
    misec = (select (extract(microsecond from $1::time))::integer);
    sec = (select (extract(second from $1::time))::integer);
    ret = misec - sec * 1000000;

    return ret;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.quarter(date)
RETURNS integer
AS
$$
    select (extract(quarter from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.quarter(timestamp)
RETURNS integer
AS
$$
    select (extract(quarter from $1))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.quarter(text)
RETURNS integer
AS
$$
    select (extract(quarter from $1::date))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.time_to_sec(timestamp)
RETURNS bigint AS $$
  SELECT EXTRACT(epoch FROM pg_catalog.time($1))::bigint
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.time_to_sec(time)
RETURNS bigint AS $$
  SELECT EXTRACT(epoch FROM pg_catalog.time($1))::bigint
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.time_to_sec(text)
RETURNS bigint AS $$
  SELECT EXTRACT(epoch FROM pg_catalog.time($1))::bigint
$$ IMMUTABLE STRICT LANGUAGE SQL;

---- SEC_TO_TIME()
CREATE OR REPLACE FUNCTION mysql.sec_to_time(bigint)
RETURNS time AS $$
  SELECT $1 * '1 second'::pg_catalog.interval
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION period_add(integer, integer)
RETURNS text
AS
$$
DECLARE
    arg1 text;
    period text;
    base date;
    baseyear integer;
BEGIN
    arg1 = $1::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period := arg1;
    END IF;

    IF pg_catalog.length(period) = 4 THEN
        baseyear := substring(period FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        base := (baseyear operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 3) operator(pg_catalog.||) '-01')::date;
    ELSIF pg_catalog.length(period) = 6 THEN
    base := (SUBSTRING(period FROM 1 FOR 4) operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 5) operator(pg_catalog.||) '-01')::date;
    ELSE
        RETURN NULL;
    END IF;

    base := base + ('1 month'::pg_catalog.interval * $2);
    RETURN pg_catalog.lpad(extract(year from base)::text, 4, '0') operator(pg_catalog.||) pg_catalog.lpad(extract(month from base)::text, 2, '0');
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION period_diff(integer, integer)
RETURNS integer
AS
$$
DECLARE
    arg1 text;
    arg2 text;
    baseyear integer;
    period1 text;
    period2 text;
    months1 integer;
    months2 integer;
BEGIN
    arg1 = $1::text;
    arg2 = $2::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period1 := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period1 := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period1 := arg1;
    END IF;

    IF pg_catalog.length(period1) = 4 THEN
        baseyear := SUBSTRING(period1 FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        months1 := baseyear * 12 + SUBSTRING(period1 FROM 3)::integer;
    ELSIF pg_catalog.length(period1) = 6 THEN
        months1 := SUBSTRING(period1 FROM 1 FOR 4)::integer * 12 + SUBSTRING(period1 FROM 5)::integer;
    ELSE
        RETURN NULL;
    END IF;

    IF pg_catalog.length(arg2) < 4 THEN
        period2 := pg_catalog.lpad(arg2, 4, 0);
    ELSIF pg_catalog.length(arg2) = 5 THEN
        period2 := pg_catalog.lpad(arg2, 6, 0);
    ELSE
        period2 := arg2;
    END IF;

    IF pg_catalog.length(period2) = 4 THEN
        baseyear := SUBSTRING(period2 FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        months2 := baseyear * 12 + SUBSTRING(period2 FROM 3)::integer;
    ELSIF pg_catalog.length(period2) = 6 THEN
        months2 := SUBSTRING(period2 FROM 1 FOR 4)::integer * 12 + SUBSTRING(period2 FROM 5)::integer;
    ELSE
        RETURN NULL;
    END IF;

    RETURN months1 - months2;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

-- '0000-01-01'不在halo的date类型范围内
-- XXX: Haven't done integer variant
CREATE OR REPLACE FUNCTION mysql.to_days(date)
RETURNS integer
AS
$$
    SELECT ($1 - '2000-01-01'::date) + 730485
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.from_days(integer)
RETURNS date
AS
$$
    SELECT ('2000-01-01'::date + ($1 - 730485) * '1 day'::pg_catalog.interval)::date
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.length(text)
RETURNS integer
AS 'textoctetlen'
LANGUAGE internal
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.length(in num char)
RETURNS integer
AS
$$
DECLARE
    ret integer;
BEGIN
    ret = (select mysql.length(num::text));

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.length(in num int)
RETURNS integer
AS
$$
DECLARE
    ret integer;
BEGIN
    ret = (select mysql.length(num::text));

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.length(in num mysql.smallint)
RETURNS integer
AS
$$
DECLARE
    ret integer;
BEGIN
    ret = (select mysql.length(num::text));

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.length(in num bigint)
RETURNS integer
AS
$$
DECLARE
    ret integer;
BEGIN
    ret = (select mysql.length(num::text));

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.length(in num numeric)
RETURNS integer
AS
$$
DECLARE
    ret integer;
BEGIN
    ret = (select mysql.length(num::text));

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(text, int)
RETURNS text
AS '$libdir/mysm', 'text_substr_no_len'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.substring(mysql.smallint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(bigint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(date, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(time, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(timestamp, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(timestamptz, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(text, int, int)
RETURNS text
AS '$libdir/mysm', 'text_substr'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.substring(mysql.smallint, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(int, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(bigint, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(date, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(time, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(timestamp, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substring(timestamptz, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.text_locate2(text, text)
RETURNS integer
AS '$libdir/mysm', 'text_locate2'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.locate(text, text)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, text)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, numeric)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, numeric)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, time)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, time)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, timestamp)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, timestamp)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, timestamptz)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, timestamptz)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate2($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.text_locate3(text, text, bigint)
RETURNS integer
AS '$libdir/mysm', 'text_locate3'
LANGUAGE C
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.locate(text, text, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, text, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, numeric, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1, $2::text, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, numeric, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1::text, $2::text, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, time, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, time, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1::text, $2::text, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, timestamp, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1, $2::text, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, timestamp, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1::text, $2::text, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(text, timestamptz, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1, $2::text, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.locate(numeric, timestamptz, integer)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_locate3($1::text, $2::text, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.left(text, int)
RETURNS text
AS '$libdir/mysm', 'text_left'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.left(mysql.smallint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.left($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.left(int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.left($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.left(bigint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.left($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.left(date, int)
RETURNS text
AS
$$
BEGIN
    return mysql.left($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.left(time, int)
RETURNS text
AS
$$
BEGIN
    return mysql.left($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.left(timestamp, int)
RETURNS text
AS
$$
BEGIN
    return mysql.left($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.left(timestamptz, int)
RETURNS text
AS
$$
BEGIN
    return mysql.left($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(text, integer)
RETURNS text
AS '$libdir/mysm', 'text_right'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.right(mysql.smallint, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(integer, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(bigint, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(numeric, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(time, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(date, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(timestamp, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.right(timestamptz, integer)
RETURNS text
AS
$$
BEGIN
    return mysql.right($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.concat(VARIADIC pg_catalog.any)
RETURNS text
AS '$libdir/mysm', 'text_concat'
LANGUAGE C
STABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.lcase(text)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(mysql.smallint)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(integer)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(bigint)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(numeric)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(time)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(date)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(timestamp)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lcase(timestamptz)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.lower($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(text)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(mysql.smallint)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(integer)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(bigint)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(numeric)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(time)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(date)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(timestamp)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ucase(timestamptz)
RETURNS text
AS
$$
BEGIN
    return pg_catalog.upper($1::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.array_to_string_for_mysql(anyarray, text)
RETURNS text
AS
$$
DECLARE
    ret text;
    x text;
    sep_count int;
    null_count int;
    array_index int;
BEGIN
    ret = '';
    sep_count = 0;
    null_count = 0;
    array_index = 0;

    if $1 is not null then
        foreach x in array $1
        loop
            if x is NULL then
                null_count = null_count + 1;
                --ret = ret || 'NULL';
            elsif length(x) = 0 then
                if 0 < sep_count then
                    ret = ret || $2;
                end if;
                sep_count = sep_count + 1;

                ret = ret || '';
            else
                if 0 < sep_count then
                    ret = ret || $2;
                end if;
                sep_count = sep_count + 1;

                ret = ret || x;
            end if;

            array_index = array_index + 1;
        end loop;

        if array_index <= null_count then
            ret = NULL;
        end if;
    else
        ret = NULL;
    end if;

    return ret;
end
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.strcmp(pg_catalog.text, pg_catalog.text)
RETURNS pg_catalog.int4
AS
$$
BEGIN
    if $1 = $2 then
        return 0;
    elsif $1 < $2 then
        return -1;
    else
        return 1;
    end if;
END
$$
strict language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.insert(text, int, int, text)
RETURNS text
AS
$$
DECLARE
    ret text;
    start_index int;
    len int;
BEGIN
    start_index = $2;
    len = $3;

    if 0 < start_index then
        if start_index <= length($1) then
            if len < 0 then
                len = length($1) + 1 - start_index;
            end if;

            ret = (select pg_catalog.overlay($1, $4, start_index, len));
        else
            ret = $1;
        end if;
    else
        ret = $1;
    end if;

    return ret;
END
$$
strict language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.rand()
RETURNS numeric
AS
$$
BEGIN
    return pg_catalog.random();
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.rand(integer)
RETURNS numeric
AS
$$
BEGIN
    return pg_catalog.random();
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.rand(bigint)
RETURNS numeric
AS
$$
BEGIN
    return pg_catalog.random();
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.truncate(numeric, integer)
RETURNS numeric
AS
$$
BEGIN
    return pg_catalog.trunc($1, $2);
END
$$
IMMUTABLE STRICT language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.find_in_set(text, text)
RETURNS integer
AS
$$
DECLARE
    ret  integer;
BEGIN
    if $1 is not null and $2 is not null then
        ret = (select array_position(string_to_array($2, ','), $1));
        if ret is null then
            ret = 0;
        end if;
    else
        ret = null;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.find_in_set(bigint, text)
RETURNS integer
AS
$$
DECLARE
    ret  integer;
BEGIN
    if $1 is not null and $2 is not null then
        ret = (select array_position(string_to_array($2, ','), $1::text));
        if ret is null then
            ret = 0;
        end if;
    else
        ret = null;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.dummy_min_sfunc_for_bytea(bytea, bytea)
RETURNS bytea
LANGUAGE plpgsql
AS $$
BEGIN
    return $2;
END
$$;

CREATE OR REPLACE FUNCTION mysql.dummy_min_finalfunc_for_bytea(bytea)
RETURNS bytea
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN $1;
END
$$;

CREATE AGGREGATE mysql.dummy_min_for_bytea(bytea) (
    SFUNC=mysql.dummy_min_sfunc_for_bytea,
    STYPE=bytea,
    FINALFUNC=mysql.dummy_min_finalfunc_for_bytea
);

CREATE OR REPLACE FUNCTION mysql.sum_text(numeric, text)
RETURNS numeric
AS
$$
DECLARE
    tmp numeric;
BEGIN
    tmp = mysql.convert_text_to_float8($2)::numeric;
    IF $1 IS NOT NULL THEN
        IF tmp IS NOT NULL THEN
            return ($1 + tmp);
        ELSE
            return $1;
        END IF;
    ELSE
        return tmp;
    END IF;
END
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.sum_text_final(numeric)
RETURNS numeric
AS
$$
BEGIN
    return $1;
END
$$
LANGUAGE plpgsql;

CREATE AGGREGATE mysql.sum(text) (
    SFUNC=mysql.sum_text,
    STYPE=numeric,
    FINALFUNC=mysql.sum_text_final
);

CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.numeric)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.int8)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.int4)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.int2)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.numeric)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.int8)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.int4)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.int2)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.conv(pg_catalog.int8, pg_catalog.int4, pg_catalog.int4)
RETURNS pg_catalog.text
AS
$$
BEGIN
    if $2 = 10 then
        if $3 = 2 then
            return mysql.convert_bigint_to_varbit($1)::pg_catalog.text;
        elsif $3 = 16 then
            return to_hex($1);
        elsif $3 = 10 then
            if 0 <= $1 then
                return $1;
            else
                raise exception 'unsupport data scope';
            end if;
        else
            raise exception 'unsupport number system';
        end if;
    else
        raise exception 'unsupport number system';
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.is_valid_binary(text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'isValidBinary'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.convert_text_varbit_to_bigint(text)
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'convertTextVarbitToBigint'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.is_valid_hex(text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'isValidHex'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.is_numeric(pg_catalog.text)
RETURNS pg_catalog.bool
AS
$$
BEGIN
    RETURN $1 ~ '^([+-]?[0-9]+[.]?[0-9]*|[.][0-9]+)$';
END
$$
LANGUAGE plpgsql STRICT VOLATILE;

CREATE OR REPLACE FUNCTION mysql.convert_text_to_int8(text)
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'convertTextToInt8'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.convert_text_hex_to_text_varbit(text)
RETURNS pg_catalog.text
AS '$libdir/mysm', 'convertTextHexToTextVarbit'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.conv(pg_catalog.text, pg_catalog.int4, pg_catalog.int4)
RETURNS pg_catalog.text
AS
$$
DECLARE
    isValidBin pg_catalog.bool;
    isValidHex pg_catalog.bool;
    tmp pg_catalog.int8;
BEGIN
    if $2 = 2 then
        isValidBin = mysql.is_valid_binary($1);
        if isValidBin = true then
            if $3 = 2 then
                return $1;
            elsif $3 = 10 then
                tmp = mysql.convert_text_varbit_to_bigint($1);
                if tmp is not null then
                    return tmp::pg_catalog.text;
                else
                    raise exception 'unsupport data scope';
                end if;
            elsif $3 = 16 then
                return to_hex(mysql.convert_text_varbit_to_bigint($1))::pg_catalog.text;
            else
                raise exception 'unsupport number system';
            end if;
        else
            return '0';
        end if;
    elsif $2 = 10 then
        tmp = mysql.convert_text_to_int8($1);
        if $3 = 2 then
            return mysql.convert_bigint_to_varbit(tmp)::pg_catalog.text;
        elsif $3 = 16 then
            return to_hex(tmp);
        elsif $3 = 10 then
            if 0 <= tmp then
                return tmp;
            else
                raise exception 'unsupport data scope';
            end if;
        else
            raise exception 'unsupport number system';
        end if;
    elsif $2 = 16 then
        isValidHex = mysql.is_valid_hex($1);
        if isValidHex = true then
            if $3 = 2 then
                return mysql.convert_text_hex_to_text_varbit($1);
            elsif $3 = 10 then
                tmp = mysql.convert_text_varbit_to_bigint(mysql.convert_text_hex_to_text_varbit($1));
                if tmp is not null then
                    return tmp::pg_catalog.text;
                else
                    raise exception 'unsupport data scope';
                end if;
            elsif $3 = 16 then
                return $1;
            else
                raise exception 'unsupport number system';
            end if;
        else
            return '0';
        end if;
    else
        raise exception 'unsupport number system';
    end if;
END
$$
STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.texteq(text, text)
returns pg_catalog.bool
AS '$libdir/mysm', 'texteq_mys'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.text_instr(text, text)
RETURNS integer
AS '$libdir/mysm', 'text_instr'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.instr(text, text)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(text, numeric)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(numeric, text)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(numeric, numeric)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(time, text)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(time, numeric)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(timestamp, text)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(timestamp, numeric)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(timestamptz, text)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.instr(timestamptz, numeric)
RETURNS integer
AS
$$
BEGIN
    return mysql.text_instr($1::text, $2::text);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.check_set(text, text)
returns pg_catalog.bool
AS '$libdir/mysm', 'check_set'
LANGUAGE C
STRICT
IMMUTABLE
PARALLEL SAFE;

CREATE OR REPLACE FUNCTION mysql.mid(text, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(mysql.smallint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(bigint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(date, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(time, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(timestamp, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(timestamptz, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(mysql.smallint, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(int, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(bigint, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(date, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(time, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(timestamp, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.mid(timestamptz, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.mid($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(text, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(mysql.smallint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(bigint, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(date, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(time, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(timestamp, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(timestamptz, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(text, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substring($1, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(mysql.smallint, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(int, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(bigint, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(date, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(time, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(timestamp, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.substr(timestamptz, int, int)
RETURNS text
AS
$$
BEGIN
    return mysql.substr($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lpad(text, int, text)
RETURNS text
AS
$$
BEGIN
    if ($1 is null) or ($2 is null) or ($3 is null) then
        return null;
    end if;

    if $2 = 0 then
        return '';
    elsif $2 < 0 then
        return null;
    end if;

    if pg_catalog.length($3) = 0 then
        if pg_catalog.length($1) < $2 then
            return null;
        end if;
    end if;

    return pg_catalog.lpad($1, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.lpad(bigint, int, text)
RETURNS text
AS
$$
BEGIN
    if ($1 is null) or ($2 is null) or ($3 is null) then
        return null;
    end if;

    if $2 = 0 then
        return '';
    elsif $2 < 0 then
        return null;
    end if;

    if pg_catalog.length($3) = 0 then
        if pg_catalog.length($1::text) < $2 then
            return null;
        end if;
    end if;

    return pg_catalog.lpad($1::text, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.rpad(text, int, text)
RETURNS text
AS
$$
BEGIN
    if ($1 is null) or ($2 is null) or ($3 is null) then
        return null;
    end if;

    if $2 = 0 then
        return '';
    elsif $2 < 0 then
        return null;
    end if;

    if pg_catalog.length($3) = 0 then
        if pg_catalog.length($1) < $2 then
            return null;
        end if;
    end if;

    return pg_catalog.rpad($1, $2, $3);
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.rpad(bigint, int, text)
RETURNS text
AS
$$
BEGIN
    if ($1 is null) or ($2 is null) or ($3 is null) then
        return null;
    end if;

    if $2 = 0 then
        return '';
    elsif $2 < 0 then
        return null;
    end if;

    if pg_catalog.length($3) = 0 then
        if pg_catalog.length($1::text) < $2 then
            return null;
        end if;
    end if;

    return pg_catalog.rpad($1::text, $2, $3);
END
$$
language 'plpgsql';

---------------------------------------------------------------------
-- 从语法文件中将timestamp转换为timestamp(0)
-- 这对函数参数和返回值没有影响，
-- 但是对declare有影响，所以decare中原来的timestamp后面要加上(6)，以保持在halo中的本意。
CREATE OR REPLACE FUNCTION mysql.now(in prec int)
RETURNS timestamp
AS
$$
DECLARE
    tmp timestamp(6);
    ret timestamp(6);
BEGIN
    tmp = (select pg_catalog.now());
    if prec = 0 then
        ret = tmp::timestamp(0);
    elsif prec = 1 then
        ret = tmp::timestamp(1);
    elsif prec = 2 then
        ret = tmp::timestamp(2);
    elsif prec = 3 then
        ret = tmp::timestamp(3);
    elsif prec = 4 then
        ret = tmp::timestamp(4);
    elsif prec = 5 then
        ret = tmp::timestamp(5);
    elsif prec = 6 then
        ret = tmp::timestamp(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''now''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.sysdate(in prec int)
RETURNS timestamp
AS
$$
DECLARE
    tmp timestamp(6);
    ret timestamp(6);
BEGIN
    tmp = (select pg_catalog.clock_timestamp());
    if prec = 0 then
        ret = tmp::timestamp(0);
    elsif prec = 1 then
        ret = tmp::timestamp(1);
    elsif prec = 2 then
        ret = tmp::timestamp(2);
    elsif prec = 3 then
        ret = tmp::timestamp(3);
    elsif prec = 4 then
        ret = tmp::timestamp(4);
    elsif prec = 5 then
        ret = tmp::timestamp(5);
    elsif prec = 6 then
        ret = tmp::timestamp(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''sysdate''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(text)
RETURNS decimal
AS
$$
DECLARE
    fin_str text;
    rt decimal;
BEGIN
    fin_str := mysql._convert_date_format_to_halo($1::text);
    rt := extract(epoch from fin_str::timestamp(6))-28800;

    RETURN rt;
END
$$
VOLATILE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.from_unixtime(float)
RETURNS timestamp AS $$
  SELECT pg_catalog.to_timestamp($1)::timestamp(6)
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_add(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    select mysql._convert_date_format_to_halo($1)::timestamp(6) + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_sub(text, pg_catalog.interval)
RETURNS timestamp AS $$
  SELECT mysql._convert_date_format_to_halo($1)::timestamp(6) - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_date_format_to_halo($1)::timestamp(6) + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_date_format_to_halo($1)::timestamp(6) - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.uuid()
RETURNS text
AS
$$
BEGIN
    return uuid_generate_v4();
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE VIEW mysql.dual AS SELECT 'X'::varchar AS dummy;
REVOKE ALL ON mysql.dual FROM PUBLIC;
GRANT SELECT, REFERENCES ON mysql.dual TO PUBLIC;

CREATE OR REPLACE FUNCTION mysql.binary_regular_expr(bigint, text)
returns pg_catalog.bool
AS
$$
    select $1::text ~ $2;
$$
immutable strict language sql;
DROP OPERATOR IF EXISTS mysql.~(integer, text);
CREATE OPERATOR mysql.~ (
    FUNCTION = mysql.binary_regular_expr,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.regular_expr(bigint, text)
returns pg_catalog.bool
AS
$$
    select $1::text ~* $2;
$$
immutable strict language sql;
DROP OPERATOR IF EXISTS mysql.~*(bigint, text);
CREATE OPERATOR mysql.~* (
    FUNCTION = mysql.regular_expr,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.binary_regular_expr_not(bigint, text)
returns pg_catalog.bool
AS
$$
    select $1::text !~ $2;
$$
immutable strict language sql;
DROP OPERATOR IF EXISTS mysql.!~(bigint, text);
CREATE OPERATOR mysql.!~ (
    FUNCTION = mysql.binary_regular_expr_not,
    LEFTARG = bigint,
    RIGHTARG = text
);

CREATE OR REPLACE FUNCTION mysql.regular_expr_not(bigint, text)
returns pg_catalog.bool
AS
$$
    select $1::text !~* $2;
$$
immutable strict language sql;
DROP OPERATOR IF EXISTS mysql.!~*(bigint, text);
CREATE OPERATOR mysql.!~* (
    FUNCTION = mysql.regular_expr_not,
    LEFTARG = bigint,
    RIGHTARG = text
);

create or replace function mysql."extract"(text, timestamp)
returns numeric
language c
IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/mysm', $function$mys_extract_timestamp$function$;

create or replace function mysql."extract"(text, time)
returns numeric
language c
IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/mysm', $function$mys_extract_time$function$;

-- 处理字符串格式的datetime (字符串中为一连串数字，且不包含微妙)
CREATE OR REPLACE FUNCTION mysql._process_for_string_number_datetime(text)
returns text
as
$$
DECLARE
    ori_str text := $1;
    ori_len int := char_length($1);
    fin_str text;
begin
    if ori_len < 6 then
        fin_str = NULL;
    elsif ori_len = 8 or ori_len = 6 then
        fin_str := concat(ori_str, ' 000000');
    elsif ori_len >= 14 then
        fin_str := concat(substring(ori_str, 1, 8), ' ', substring(ori_str, 9, 6));
    elsif ori_len = 7 then
        fin_str := concat(substring(ori_str, 1, 6), ' 0', substring(ori_str, 7, 1), '0000');
    elsif ori_len = 9 then
        fin_str := concat(substring(ori_str, 1, 6), ' ', substring(ori_str, 7, 2), '0', substring(ori_str, 9, 1), '00');
    elsif ori_len = 10 then
        fin_str := concat(substring(ori_str, 1, 6), ' ', substring(ori_str, 7, 4), '00');
    elsif ori_len = 11 then
        fin_str := concat(substring(ori_str, 1, 6), ' ', substring(ori_str, 7, 4), '0', substring(ori_str, 11, 1));
    elsif ori_len = 12 or ori_len = 13 then
        fin_str := concat(substring(ori_str, 1, 6), ' ', substring(ori_str, 7, 6));
    end if;

    return fin_str;
end
$$
VOLATILE STRICT
LANGUAGE 'plpgsql';

-- 传入的参数应该是用引号引用的全数字格式的date或datetime('20221010134520.123456', ...)
CREATE OR REPLACE FUNCTION mysql._convert_format_to_halo_for_string_number_datetime(text)
RETURNS text
AS
$$
DECLARE
    ori_str text := $1;
    ori_len int;
    ori_len_before_point int;
    fin_str text;
    fin_len int;
    single_point_index int;
BEGIN
    ori_len := char_length(ori_str);
    single_point_index := position('.' in ori_str);

    if single_point_index = 0 then
        fin_str = mysql._process_for_string_number_datetime(ori_str);
    else
        -- TODO:
        -- '240111110101091.132'  ->  '2401-11-11 01:01:09.000000'
        -- '24011111010109.1.132' ->  '2401-11-11 01:01:09.100000'
        -- '24011111.010109.1132' ->  '2401-11-11 01:01:09.113200'
        ori_len_before_point := single_point_index - 1;
        fin_str := mysql._process_for_string_number_datetime(substring(ori_str, 1, ori_len_before_point));
        if fin_str is not NULL then
            if single_point_index != ori_len then
                -- '20221010134520.123456', '.'的后面还跟有微妙
                fin_str := concat(fin_str, substring(ori_str, single_point_index));
            end if;
        end if;
    end if;

    RETURN fin_str;
END
$$
VOLATILE LANGUAGE 'plpgsql';

-- 传入的参数应该是用引号引用的date或datetime格式('2022-10-10 13:45:20.123456', ...)
CREATE OR REPLACE FUNCTION mysql._convert_format_to_halo_for_string_string_datetime(text)
RETURNS text
AS
$$
DECLARE
    ori_str text := $1;
    ori_len int;
    fin_str text;
    single_point_index int;
BEGIN
    ori_len := char_length(ori_str);
    single_point_index := position('.' in ori_str);

    if single_point_index = ori_len then
        fin_str := substring(ori_str, 1, single_point_index - 1);
    else
        fin_str := ori_str;
    end if;

    RETURN fin_str;
END
$$
VOLATILE LANGUAGE 'plpgsql';

-- 传入的参数应该是引号引用的date或datetime格式，也有可能是引号引用的全数字('2022-10-10 13:45:20.123456', '20221010134520.123456', ...)
CREATE OR REPLACE FUNCTION mysql._convert_format_to_halo_for_string_datetime(text)
RETURNS text
AS
$$
DECLARE
    ori_str text := $1;
    ori_len int;
    fin_str text;
BEGIN
    ori_len := char_length(ori_str);

    if position('-' in ori_str) = 0 and position('/' in ori_str) = 0 and position(':' in ori_str) = 0 and position('..' in ori_str) = 0 then
        fin_str := mysql._convert_format_to_halo_for_string_number_datetime(ori_str);
    else
        fin_str := mysql._convert_format_to_halo_for_string_string_datetime(ori_str);
    end if;

    RETURN fin_str;
END
$$
VOLATILE STRICT
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql._date_padding(text)
RETURNS text
AS
$$
DECLARE
    ori_str text := $1;
    ori_len int := char_length($1);
    rt_str text;
BEGIN
    if ori_len = 3 then
        rt_str := concat('000', ori_str);
    elsif ori_len = 4 then
        rt_str := concat('00', ori_str);
    elsif ori_len = 5 then
        rt_str := concat('0', ori_str);
    elsif ori_len = 7 then
        if substring(ori_str, 1, 1) = '0' then
            rt_str := substring(ori_str, 2);
        else
            rt_str := ori_str;
        end if;
    elsif ori_len = 6 or ori_len = 8 then
        rt_str := ori_str;
    else
        rt_str := NULL;
    end if;

    return rt_str;
END
$$
VOLATILE STRICT
LANGUAGE 'plpgsql';

-- 处理输入为数字且不包含微妙的datetime (用户输入的数据未使用引号引用)
CREATE OR REPLACE FUNCTION mysql._process_for_number_datetime(text)
returns text
as
$$
DECLARE
    ori_str text := $1;
    ori_len int := char_length($1);
    fin_str text;
    tm_date text;
    tm_time text;
begin
    if ori_len <= 8 then
        -- 不存在time
        fin_str := mysql._date_padding(ori_str);
    else
        -- 存在time
        tm_date := mysql._date_padding(substring(ori_str, 1, ori_len - 6));
        if tm_date is not null then
            tm_time := substring(ori_str, ori_len - 6 + 1);
            fin_str := concat(tm_date, tm_time);
        else
            fin_str := NULL;
        end if;
    end if;

    return fin_str;
end
$$
VOLATILE STRICT
LANGUAGE 'plpgsql';

-- 传入的参数应该是全数字转换成的text('20221010134520.123456', ...)
CREATE OR REPLACE FUNCTION mysql._convert_format_to_halo_for_number_datetime(text)
RETURNS text
AS
$$
DECLARE
    ori_str text := $1;
    ori_len int;
    ori_len_before_point int;
    fin_str text;
    fin_len int;
    single_point_index int;
BEGIN
    ori_len := char_length(ori_str);
    single_point_index := position('.' in ori_str);

    if single_point_index = 0 then
        fin_str := mysql._process_for_number_datetime(ori_str);
    else
        ori_len_before_point := single_point_index - 1;
        fin_str := mysql._process_for_number_datetime(substring(ori_str, 1, ori_len_before_point));
        fin_len := char_length(fin_str);

        if fin_str is not null and (fin_len = 12 or fin_len = 14) then
            if single_point_index != ori_len then
                -- 补上微妙
                fin_str := concat(fin_str, substring(ori_str, single_point_index));
            end if;
        end if;
    end if;

    RETURN fin_str;
END
$$
VOLATILE STRICT
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.numeric_timestamp(numeric)
RETURNS timestamp
AS
$$
DECLARE
    ori_str text := $1::text;
    ori_len int;
    ori_len_before_point int;
    fin_str text;
    fin_len int;
    single_point_index int;
BEGIN
    ori_len := char_length(ori_str);
    single_point_index := position('.' in ori_str);

    if single_point_index = 0 then
        fin_str := mysql._process_for_number_datetime(ori_str);
    else
        ori_len_before_point := single_point_index - 1;
        fin_str := mysql._process_for_number_datetime(substring(ori_str, 1, ori_len_before_point));
        fin_len := char_length(fin_str);

        if fin_str is not null and (fin_len = 12 or fin_len = 14) then
            if single_point_index != ori_len then
                -- 补上微妙
                fin_str := concat(fin_str, substring(ori_str, single_point_index));
            end if;
        end if;
    end if;

    RETURN fin_str;
END
$$
VOLATILE STRICT
LANGUAGE 'plpgsql';

----CREATE OR REPLACE FUNCTION mysql.booleaneqbigint(pg_catalog.bool, bigint)
----RETURNS pg_catalog.bool
----AS
----$$
----BEGIN
----    if ($1 is null) or ($2 is null) then
----        return null;
----    end if;
----
----    if $1 then
----        if $2 = 1 then
----            return true;
----        else
----            return false;
----        end if;
----    else
----        if $2 = 0 then
----            return true;
----        else
----            return false;
----        end if;
----    end if;
----END
----$$
----language 'plpgsql';

-- 修改旧版本已有的函数 -------------------------------
drop function if exists mysql._convert_date_format_to_halo(text);
drop function if exists mysql.unix_timestamp(bigint);
drop function if exists mysql.unix_timestamp(integer);
drop function if exists mysql.unix_timestamp(date);

-- CREATE OR REPLACE FUNCTION mysql.unix_timestamp(text)
-- RETURNS decimal
-- AS
-- $$
-- DECLARE
--     fin_str text;
--     rt decimal;
-- BEGIN
--     fin_str := mysql._convert_format_to_halo_for_string_datetime($1);
--     rt := extract(epoch from fin_str::timestamp(6))-28800;

--     RETURN rt;
-- END
-- $$
-- VOLATILE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(text)
RETURNS decimal
AS
$$
DECLARE
    fin_str text := $1;
    rt decimal;
BEGIN
    -- rt := extract(epoch from fin_str::timestamp(6))-28800;
    rt := extract(epoch from fin_str::timestamp(6)::timestamptz(6));

    RETURN rt;
END
$$
VOLATILE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.unix_timestamp(numeric)
RETURNS decimal
AS
$$
DECLARE
    fin_str text;
    rt decimal;
BEGIN
    fin_str := mysql._convert_format_to_halo_for_number_datetime($1::text);
    -- rt := extract(epoch from fin_str::timestamp(6))-28800;
    rt := extract(epoch from fin_str::timestamp(6)::timestamptz(6));

    RETURN rt;
END
$$
VOLATILE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.date(numeric)
RETURNS date
AS
$$
DECLARE
    fin_str text;
    rt date;
BEGIN
    fin_str := mysql._convert_format_to_halo_for_number_datetime($1::text);
    rt := (select fin_str::date);

    RETURN rt;
END
$$
VOLATILE LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.utc_date()
RETURNS date
AS
$$
    SELECT (CURRENT_TIMESTAMP::pg_catalog.timestamptz AT TIME ZONE 'UTC')::date
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.utc_time()
RETURNS time
AS
$$
    SELECT (CURRENT_TIMESTAMP::pg_catalog.timestamptz AT TIME ZONE 'UTC')::time(0)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.utc_time(in prec int)
RETURNS time
AS
$$
DECLARE
    tmp time(6);
    ret time(6);
BEGIN
    tmp = (SELECT (CURRENT_TIMESTAMP(6)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::time(6));
    if prec = 0 then
        ret = tmp::time(0);
    elsif prec = 1 then
        ret = tmp::time(1);
    elsif prec = 2 then
        ret = tmp::time(2);
    elsif prec = 3 then
        ret = tmp::time(3);
    elsif prec = 4 then
        ret = tmp::time(4);
    elsif prec = 5 then
        ret = tmp::time(5);
    elsif prec = 6 then
        ret = tmp::time(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''utc_time''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.utc_timestamp()
RETURNS timestamp
AS
$$
    SELECT (CURRENT_TIMESTAMP::pg_catalog.timestamptz AT TIME ZONE 'UTC')::timestamp(0)
$$
VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.utc_timestamp(in prec int)
RETURNS timestamp
AS
$$
DECLARE
    tmp timestamp(6);
    ret timestamp(6);
BEGIN
    tmp = (SELECT (CURRENT_TIMESTAMP(6)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::timestamp(6));
    if prec = 0 then
        ret = tmp::timestamp(0);
    elsif prec = 1 then
        ret = tmp::timestamp(1);
    elsif prec = 2 then
        ret = tmp::timestamp(2);
    elsif prec = 3 then
        ret = tmp::timestamp(3);
    elsif prec = 4 then
        ret = tmp::timestamp(4);
    elsif prec = 5 then
        ret = tmp::timestamp(5);
    elsif prec = 6 then
        ret = tmp::timestamp(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''utc_timestamp''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.curtime(in prec int)
RETURNS time
AS
$$
DECLARE
    ret time(6);
BEGIN
    if prec = 0 then
        ret = (select current_time(0));
    elsif prec = 1 then
        ret = (select current_time(1));
    elsif prec = 2 then
        ret = (select current_time(2));
    elsif prec = 3 then
        ret = (select current_time(3));
    elsif prec = 4 then
        ret = (select current_time(4));
    elsif prec = 5 then
        ret = (select current_time(5));
    elsif prec = 6 then
        ret = (select current_time(6));
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''curtime''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.timestampadd(text, integer, timestamp without time zone)
RETURNS timestamp without time zone
AS
$$
DECLARE
    result timestamp(6);
BEGIN
    if $1 = 'quarter' then
        SELECT $3 + ($2 operator(pg_catalog.||) ' month')::pg_catalog.interval * 3 into result;
    else
        SELECT $3 + ($2 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $1)::pg_catalog.interval into result;
    end if;

    return result;
END
$$
IMMUTABLE STRICT
LANGUAGE plpgsql;

-- TIME_FORMAT()
drop function if exists mysql.time_format(pg_catalog.interval, text);
CREATE OR REPLACE FUNCTION mysql.time_format(time, text)
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
        -- Look at current character
        c := substring($2 FROM i FOR 1);
        -- If it's a '%' and not the last character then process it as a placeholder
        IF c = '%' AND i != len THEN
            n := (substring($2 FROM (i + 1) FOR 1))::character;
            SELECT INTO res CASE
            WHEN n =# 'a' THEN '0'
            WHEN n =# 'b' THEN '0'
            WHEN n =# 'c' THEN '0'
            WHEN n =# 'D' THEN '0'
            WHEN n =# 'd' THEN '00'
            WHEN n =# 'e' THEN '0'
            WHEN n =# 'f' THEN pg_catalog.to_char($1, 'US')
            WHEN n =# 'H' THEN pg_catalog.to_char($1, 'HH24')
            WHEN n =# 'h' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'I' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'i' THEN pg_catalog.to_char($1, 'MI')
            WHEN n =# 'j' THEN '0'
            WHEN n =# 'k' THEN pg_catalog.to_char($1, 'FMHH24')
            WHEN n =# 'l' THEN (pg_catalog.to_char($1, 'FMHH12')::integer % 12)::text
            WHEN n =# 'M' THEN '0'
            WHEN n =# 'm' THEN '00'
            WHEN n =# 'p' THEN pg_catalog.to_char($1, 'AM')
            WHEN n =# 'r' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
                operator(pg_catalog.||)
                pg_catalog.to_char($1, ':MI:SS ')
                operator(pg_catalog.||)
                CASE WHEN pg_catalog.to_char($1, 'FMHH24')::integer <= 11 THEN 'AM' ELSE 'PM' END
            WHEN n =# 'S' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 's' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 'T' THEN pg_catalog.to_char($1, 'HH24:MI:SS')
            WHEN n =# 'U' THEN '0'
            WHEN n =# 'u' THEN '0'
            WHEN n =# 'V' THEN '0'
            WHEN n =# 'v' THEN '0'
            WHEN n =# 'W' THEN '0'
            WHEN n =# 'w' THEN '0'
            WHEN n =# 'X' THEN '0'
            WHEN n =# 'x' THEN '0'
            WHEN n =# 'Y' THEN '0000'
            WHEN n =# 'y' THEN '00'
            WHEN n =# '%' THEN pg_catalog.to_char($1, '%')
            ELSE NULL
            END;
            if res is not null then
                temp := temp operator(pg_catalog.||) res;
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            -- Otherwise just append the character to the string
            temp = temp operator(pg_catalog.||) c;
            i := i + 1;
        END IF;
    END LOOP;
    RETURN temp;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

drop function if exists mysql.time_format(timestamp, text);
-- CREATE OR REPLACE FUNCTION mysql.time_format(timestamp, text)
-- RETURNS text AS $$
-- select mysql.time_format($1::time::pg_catalog.interval, $2)
-- $$ IMMUTABLE STRICT LANGUAGE SQL;

drop function if exists mysql.time_format(text, text);
-- CREATE OR REPLACE FUNCTION mysql.time_format(text, text)
-- RETURNS text AS $$
-- select mysql.time_format($1::pg_catalog.interval, $2)
-- $$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.makedate(integer, integer)
RETURNS date
AS
$$
    select
        CASE WHEN $2 > 0 THEN
            (($1 operator(pg_catalog.||) '-01-01')::date + ($2 - 1) * '1 day'::pg_catalog.interval)::date
        ELSE
            NULL
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

drop function if exists mysql.maketime(integer, integer, integer);
CREATE OR REPLACE FUNCTION mysql.maketime(integer, integer, numeric)
RETURNS time
AS
$$
    select ($1 operator(pg_catalog.||) ':' operator(pg_catalog.||) $2 operator(pg_catalog.||) ':' operator(pg_catalog.||) $3)::time(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_tz(timestamp, text, text)
RETURNS timestamp
AS
$$
    SELECT
        CASE WHEN POSITION(':' IN $3) = 0 THEN
            ($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp(6) with time zone AT TIME ZONE $3
        ELSE
            ($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp(6) with time zone AT TIME ZONE $3::pg_catalog.interval
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(timestamp, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT ($1 + $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(timestamp, integer)
RETURNS timestamp
AS
$$
    SELECT $1 + ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

-- adddate('2023-06-09'::date, interval 1 second)返回结果应为timestamp
CREATE OR REPLACE FUNCTION mysql.adddate(date, pg_catalog.interval)
RETURNS date
AS
$$
    SELECT ($1 + $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(date, integer)
RETURNS date
AS
$$
    SELECT $1 + ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1::timestamp(6) + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(text, integer)
RETURNS timestamp
AS
$$
    SELECT $1::timestamp(6) + ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(numeric, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6) + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.adddate(numeric, integer)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6) + ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_add(timestamp, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1 + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

-- date_add('2023-06-09'::date, interval 1 second)返回结果应为timestamp
CREATE OR REPLACE FUNCTION mysql.date_add(date, pg_catalog.interval)
RETURNS date
AS
$$
    SELECT $1 + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_add(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    select $1::timestamp(6) + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_add(numeric, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6) + $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_sub(timestamp, pg_catalog.interval)
RETURNS timestamp AS $$
  SELECT $1 - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

-- date_sub('2023-06-09'::date, interval 1 second)返回结果应为timestamp
CREATE OR REPLACE FUNCTION mysql.date_sub(date, pg_catalog.interval)
RETURNS date AS $$
  SELECT $1 - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_sub(text, pg_catalog.interval)
RETURNS timestamp
AS $$
    SELECT $1::timestamp(6) - $2
$$ IMMUTABLE STRICT
LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_sub(numeric, pg_catalog.interval)
RETURNS timestamp AS $$
  SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6) - $2
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(timestamp, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1 - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(date, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1 - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(text, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT $1::timestamp(6) - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(numeric, pg_catalog.interval)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6) - $2
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(timestamp, integer)
RETURNS timestamp
AS
$$
    SELECT $1 - ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(date, integer)
RETURNS date
AS
$$
    SELECT $1 - ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(text, integer)
RETURNS timestamp
AS
$$
    SELECT $1::timestamp(6) - ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subdate(numeric, integer)
RETURNS timestamp
AS
$$
    SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6) - ('1 day'::pg_catalog.interval * $2)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(text, text)
RETURNS integer AS $$
    SELECT $1::date - $2::date
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(numeric, numeric)
RETURNS integer AS $$
    SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::date - mysql._convert_format_to_halo_for_number_datetime($2::text)::date
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(numeric, text)
RETURNS integer AS $$
    SELECT mysql._convert_format_to_halo_for_number_datetime($1::text)::date - $2::date
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.datediff(text, numeric)
RETURNS integer AS $$
    SELECT $1::date - mysql._convert_format_to_halo_for_number_datetime($2::text)::date
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.year(text)
RETURNS integer
AS $$
    SELECT EXTRACT(YEAR FROM $1::timestamp)::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.year(numeric)
RETURNS integer
AS $$
    SELECT EXTRACT(YEAR FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.quarter(text)
RETURNS integer
AS
$$
    select (extract(quarter from $1::timestamp))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.quarter(numeric)
RETURNS integer
AS
$$
    select (extract(quarter from mysql._convert_format_to_halo_for_number_datetime($1::text)::date))::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.month(text)
RETURNS integer
AS $$
    SELECT EXTRACT(MONTH FROM $1::timestamp)::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.month(numeric)
RETURNS integer
AS $$
    SELECT EXTRACT(MONTH FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.monthname(text)
RETURNS text
AS $$
    SELECT pg_catalog.to_char($1::timestamp(6), 'FMMonth')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.monthname(numeric)
RETURNS text
AS $$
    SELECT pg_catalog.to_char(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6), 'FMMonth')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.day(text)
RETURNS integer
AS $$
    SELECT EXTRACT(DAY FROM $1::timestamp)::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.day(numeric)
RETURNS integer
AS $$
    SELECT EXTRACT(DAY FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayname(text)
RETURNS text
AS $$
    SELECT pg_catalog.to_char($1::timestamp(6), 'FMDay')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayname(numeric)
RETURNS text
AS $$
    SELECT pg_catalog.to_char(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp(6), 'FMDay')
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofmonth(text)
RETURNS integer AS $$
  SELECT EXTRACT(DAY FROM $1::timestamp)::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofmonth(numeric)
RETURNS integer AS $$
  SELECT EXTRACT(DAY FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofweek(text)
RETURNS integer AS $$
  SELECT EXTRACT(DOW FROM $1::timestamp)::integer + 1
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofweek(numeric)
RETURNS integer AS $$
  SELECT EXTRACT(DOW FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer + 1
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofyear(text)
RETURNS integer AS $$
  SELECT EXTRACT(DOY FROM $1::timestamp)::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.dayofyear(numeric)
RETURNS integer AS $$
  SELECT EXTRACT(DOY FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.week(text, integer)
RETURNS integer AS $$
  SELECT (_calc_week($1::date, _week_mode($2)))[1];
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.week(numeric, integer)
RETURNS integer AS $$
  SELECT (_calc_week(DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp), _week_mode($2)))[1];
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.yearweek(qdate text, mode integer)
RETURNS integer AS $$
  DECLARE
    _WEEK_YEAR CONSTANT integer := 2;
    a integer[] := _calc_week(qdate::date, _week_mode(mode | _WEEK_YEAR));
    week integer := a[1];
    year integer := a[2];
  BEGIN
    RETURN week + year * 100;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.yearweek(qdate numeric, mode integer)
RETURNS integer AS $$
  DECLARE
    _WEEK_YEAR CONSTANT integer := 2;
    a integer[] := _calc_week(DATE(mysql._convert_format_to_halo_for_number_datetime(qdate::text)::timestamp), _week_mode(mode | _WEEK_YEAR));
    week integer := a[1];
    year integer := a[2];
  BEGIN
    RETURN week + year * 100;
  END;
$$ IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.weekday(text)
RETURNS integer AS $$
  SELECT CASE
    WHEN EXTRACT(DOW FROM $1::date)::integer = 0 THEN
      6
    ELSE
      EXTRACT(DOW FROM $1::date)::integer - 1
    END
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.weekday(numeric)
RETURNS integer AS $$
    SELECT CASE
    WHEN EXTRACT(DOW FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer = 0 THEN
      6
    ELSE
      EXTRACT(DOW FROM DATE(mysql._convert_format_to_halo_for_number_datetime($1::text)::timestamp))::integer - 1
    END
$$ IMMUTABLE STRICT LANGUAGE SQL;

drop function if exists mysql.timediff(text, text);
CREATE OR REPLACE FUNCTION mysql.timediff(text, text)
RETURNS time
LANGUAGE c
IMMUTABLE STRICT
AS '$libdir/mysm', $function$timediff$function$;

drop function if exists mysql.timediff(time, time);
CREATE OR REPLACE FUNCTION mysql.timediff(time, time)
RETURNS time
AS $$
    SELECT mysql.timediff($1::text, $2::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

drop function if exists mysql.timediff(timestamp, timestamp);
CREATE OR REPLACE FUNCTION mysql.timediff(timestamp, timestamp)
RETURNS time
AS $$
    SELECT mysql.timediff($1::text, $2::text)
$$ IMMUTABLE STRICT LANGUAGE SQL;

drop function if exists mysql.addtime(timestamp, pg_catalog.interval);
CREATE OR REPLACE FUNCTION mysql.addtime(timestamp, text)
RETURNS timestamp
AS
$$
    SELECT mysql.addtime($1::text, $2)::timestamp(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

drop function if exists mysql.addtime(time, pg_catalog.interval);
CREATE OR REPLACE FUNCTION mysql.addtime(time, text)
RETURNS time
AS
$$
    SELECT mysql.addtime($1::text, $2)::time(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.addtime(text, time)
RETURNS text
AS
$$
    select mysql.addtime($1, $2::text)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.addtime(timestamp, time)
RETURNS timestamp
AS
$$
    select mysql.addtime($1::text, $2::text)::timestamp(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.addtime(time, time)
RETURNS time
AS
$$
    select mysql.addtime($1::text, $2::text)::time(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

-- '2023-06-13 12:43:56'不应该返回time
-- 修改原函数的返回类型，需要先删除原函数，重新创建
drop function if exists mysql.addtime(text, pg_catalog.interval);
CREATE OR REPLACE FUNCTION mysql.addtime(text, text)
RETURNS text
LANGUAGE c
IMMUTABLE STRICT
AS '$libdir/mysm', $function$addtime$function$;

CREATE OR REPLACE FUNCTION mysql.convert_to_time_format(text)
RETURNS pg_catalog.interval
AS
$$
DECLARE
    tmp text;
    len int;
    colon_index int;
    pot_index int;
    c char;
    i int;
BEGIN
    tmp = $1;
    len = pg_catalog.length(tmp);
    colon_index = position(':' in tmp);
    pot_index = position('.' in tmp);

    if 0 < colon_index then
        return $1::pg_catalog.interval;
    else
        if pot_index = 0 then
            i = len;
        else
            i = pot_index - 1;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                i = i - 2;
            else
                return null;
            end if;
        elsif i = 2 then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                return $1::pg_catalog.interval;
            else
                return null;
            end if;
        else
            return $1::pg_catalog.interval;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        elsif 2 = i then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                tmp = '00:' operator(pg_catalog.||) tmp;
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        else
            tmp = '00:0' operator(pg_catalog.||) tmp;
            return tmp::pg_catalog.interval;
        end if;
    end if;
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.subtime(timestamp, text)
RETURNS timestamp
AS
$$
    --SELECT $1 - mysql.convert_to_time_format($2)::pg_catalog.interval
    select mysql.subtime($1::text, $2)::timestamp(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subtime(time, text)
RETURNS time
AS
$$
    --SELECT $1 - mysql.convert_to_time_format($2)::pg_catalog.interval
    select mysql.subtime($1::text, $2)::time(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subtime(text, time)
RETURNS text
AS
$$
    --SELECT $1 - mysql.convert_to_time_format($2)::pg_catalog.interval
    select mysql.subtime($1, $2::text)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subtime(timestamp, time)
RETURNS timestamp
AS
$$
    --SELECT $1 - mysql.convert_to_time_format($2)::pg_catalog.interval
    select mysql.subtime($1::text, $2::text)::timestamp(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.subtime(time, time)
RETURNS time
AS
$$
    --SELECT $1 - mysql.convert_to_time_format($2)::pg_catalog.interval
    select mysql.subtime($1::text, $2::text)::time(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

-- 修改函数返回类型，需要先删除原函数
drop function if exists mysql.subtime(text, text);
CREATE OR REPLACE FUNCTION mysql.subtime(text, text)
RETURNS text
LANGUAGE c
IMMUTABLE STRICT
AS '$libdir/mysm', $function$subtime$function$;

CREATE OR REPLACE FUNCTION mysql.last_day(date)
RETURNS date
AS
$$
    SELECT CASE WHEN EXTRACT(MONTH FROM $1) = 12 THEN
                (((extract(year from $1) + 1) operator(pg_catalog.||) '-01-01')::date - '1 day'::pg_catalog.interval)::date
           ELSE
                ((extract(year from $1) operator(pg_catalog.||) '-' operator(pg_catalog.||) (extract(month from $1) + 1) operator(pg_catalog.||) '-01')::date - '1 day'::pg_catalog.interval)::date
           END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.last_day(text)
RETURNS date
AS
$$
DECLARE
    dt date;
BEGIN
    dt = $1::date;
    return mysql.last_day(dt);
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.last_day(numeric)
RETURNS date
AS
$$
DECLARE
    dt date;
BEGIN
    dt = mysql._convert_format_to_halo_for_number_datetime($1::text)::date;
    return mysql.last_day(dt);
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.sec_to_time(bigint)
RETURNS time AS $$
  SELECT $1 * '1 second'::pg_catalog.interval
$$ IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION period_add(integer, integer)
RETURNS text
AS
$$
DECLARE
    arg1 text;
    period text;
    base date;
    baseyear integer;
BEGIN
    arg1 = $1::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period := arg1;
    END IF;

    IF pg_catalog.length(period) = 4 THEN
        baseyear := substring(period FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        base := (baseyear operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 3) operator(pg_catalog.||) '-01')::date;
    ELSIF pg_catalog.length(period) = 6 THEN
    base := (SUBSTRING(period FROM 1 FOR 4) operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 5) operator(pg_catalog.||) '-01')::date;
    ELSE
        RETURN NULL;
    END IF;

    base := base + ('1 month'::pg_catalog.interval * $2);
    RETURN pg_catalog.lpad(extract(year from base)::text, 4, '0') operator(pg_catalog.||) pg_catalog.lpad(extract(month from base)::text, 2, '0');
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.from_days(integer)
RETURNS date
AS
$$
    SELECT ('2000-01-01'::date + ($1 - 730485) * '1 day'::pg_catalog.interval)::date
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.microsecond(time)
RETURNS integer
AS
$$
    select extract(microsecond from $1)::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.microsecond(timestamp)
RETURNS integer
AS
$$
    select extract(microsecond from $1)::integer
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.microsecond(text)
RETURNS integer
AS
$$
    select extract(microsecond from $1::time(6))::integer;
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.get_lock(text, int)
RETURNS int
LANGUAGE plpgsql
AS $function$
begin
    return 1;
end;
$function$;

CREATE OR REPLACE FUNCTION mysql.release_lock(text)
RETURNS int
LANGUAGE plpgsql
AS $function$
begin
    return 1;
end;
$function$;

CREATE OR REPLACE FUNCTION mysql.is_free_lock(text)
RETURNS int
LANGUAGE plpgsql
AS $function$
begin
    return 1;
end;
$function$;

CREATE OR REPLACE FUNCTION mysql.is_used_lock(text)
RETURNS int
LANGUAGE plpgsql
AS $function$
begin
    return null;
end;
$function$;

create function mysql.JSON_UNQUOTE(json)
returns text
as
$$
    select trim('"' FROM $1::text);
$$
language sql;

CREATE OR REPLACE FUNCTION mysql.isnull(val json)
RETURNS integer
LANGUAGE plpgsql
AS $function$
    DECLARE
    ret int;
BEGIN
    if coalesce(val::text) = val::text then
        ret := 0;
    else
        ret := 1;
    end if;

    return ret;
END;
$function$;

create or replace function mysql.user()
returns pg_catalog.text
as
$$
    select current_user;
$$
language sql;

create or replace function mysql.database()
returns pg_catalog.text
as
$$
    select current_schema;
$$
language sql;

create or replace function mysql.schema()
returns pg_catalog.text
as
$$
    select current_schema;
$$
language sql;

CREATE OR REPLACE FUNCTION mysql.version()
RETURNS pg_catalog.text
AS '$libdir/mysm', 'mysVersion'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.unix_timestamp()
RETURNS bigint AS $$
    SELECT (EXTRACT(EPOCH FROM LOCALTIMESTAMP::timestamptz at time zone 'UTC'))::bigint
$$ VOLATILE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.concat_ws(text, VARIADIC pg_catalog.any)
RETURNS text
AS '$libdir/mysm', 'text_concat_ws'
LANGUAGE C
STABLE
PARALLEL SAFE;

create or replace function mysql.set_user_var(variable_name varchar(64),
                                              variable_value pg_catalog.anycompatible)
returns void
as '$libdir/mysm', 'mysSetUserVar'
LANGUAGE C IMMUTABLE;

create or replace function mysql.set_user_var_in_expr(variable_name varchar(64),
                                                      variable_value pg_catalog.anycompatible)
returns pg_catalog.bytea
as '$libdir/mysm', 'mysSetUserVarInExpr'
LANGUAGE C VOLATILE;

create or replace function mysql.get_user_var(variable_name varchar(64))
returns pg_catalog.bytea
as '$libdir/mysm', 'mysGetUserVarValue'
LANGUAGE C STRICT VOLATILE;

create or replace function mysql.clear_user_variables()
returns void
as '$libdir/mysm', 'mysClearUserVariables'
language c strict immutable;

CREATE OR REPLACE FUNCTION mysql.row_count()
RETURNS int8
AS '$libdir/mysm', 'rowCount'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.found_rows()
RETURNS int8
AS '$libdir/mysm', 'mysFoundRows'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.last_insert_id()
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'mysLastInsertId'
LANGUAGE C STRICT VOLATILE;

CREATE OR REPLACE FUNCTION mysql.substring_index(pg_catalog.text, pg_catalog.text, pg_catalog.int4)
RETURNS pg_catalog.text
AS '$libdir/mysm', 'substringIndex'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION mysql.bit_count(pg_catalog.text)
RETURNS pg_catalog.int4
AS
$$
BEGIN
    -- for bit_count(NULL)
    return null;
END
$$
VOLATILE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.bit_count(pg_catalog.int8)
RETURNS pg_catalog.int4
AS
$$
DECLARE
    num pg_catalog.int4;
BEGIN
    num = pg_catalog.bit_count($1::pg_catalog.bit(64));
    return num;
END
$$
VOLATILE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.bit_count(pg_catalog.bytea)
RETURNS pg_catalog.int4
AS
$$
BEGIN
    return mysql.bit_count($1::pg_catalog.int8);
END
$$
VOLATILE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.bit_or_varbit(pg_catalog.int8, pg_catalog.varbit)
RETURNS pg_catalog.int8
AS
$$
DECLARE
    tmp pg_catalog.int8;
BEGIN
    if $1 is not null then
        tmp = $1 | ($2::pg_catalog.int8);
    else
        tmp = $2::pg_catalog.int8;
    end if;
    return tmp;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.bit_or_varbit_final(pg_catalog.int8)
RETURNS pg_catalog.int8
AS
$$
BEGIN
    return $1;
END
$$
LANGUAGE 'plpgsql';

CREATE AGGREGATE mysql.bit_or(pg_catalog.varbit) (
    SFUNC=mysql.bit_or_varbit,
    STYPE=pg_catalog.int8,
    FINALFUNC=mysql.bit_or_varbit_final
);

CREATE OR REPLACE FUNCTION mysql.bit_and_varbit(pg_catalog.int8, pg_catalog.varbit)
RETURNS pg_catalog.int8
AS
$$
DECLARE
    tmp pg_catalog.int8;
BEGIN
    if $1 is not null then
        tmp = $1 & ($2::pg_catalog.int8);
    else
        tmp = $2::pg_catalog.int8;
    end if;
    return tmp;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.bit_and_varbit_final(pg_catalog.int8)
RETURNS pg_catalog.int8
AS
$$
BEGIN
    return $1;
END
$$
LANGUAGE 'plpgsql';

CREATE AGGREGATE mysql.bit_and(pg_catalog.varbit) (
    SFUNC=mysql.bit_and_varbit,
    STYPE=pg_catalog.int8,
    FINALFUNC=mysql.bit_and_varbit_final
);

CREATE OR REPLACE FUNCTION mysql.bit_xor_varbit(pg_catalog.int8, pg_catalog.varbit)
RETURNS pg_catalog.int8
AS
$$
DECLARE
    tmp pg_catalog.int8;
BEGIN
    if $1 is not null then
        tmp = $1 ^ ($2::pg_catalog.int8);
    else
        tmp = $2::pg_catalog.int8;
    end if;
    return tmp;
END
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.bit_xor_varbit_final(pg_catalog.int8)
RETURNS pg_catalog.int8
AS
$$
BEGIN
    return $1;
END
$$
LANGUAGE 'plpgsql';

CREATE AGGREGATE mysql.bit_xor(pg_catalog.varbit) (
    SFUNC=mysql.bit_xor_varbit,
    STYPE=pg_catalog.int8,
    FINALFUNC=mysql.bit_xor_varbit_final
);

DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 timestamp, value3 timestamp);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.tinyint, value3 mysql.tinyint);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.smallint, value3 mysql.smallint);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.mediumint, value3 mysql.mediumint);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 int, value3 int);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 bigint, value3 bigint);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 float4, value3 float4);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 float8, value3 float8);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 numeric, value3 numeric);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.double, value3 mysql.double);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.real, value3 mysql.real);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 char, value3 char);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 varchar, value3 varchar);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 text, value3 text);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 date, value3 date);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 time, value3 time);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.datetime, value3 mysql.datetime);
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 timestamp, value3 timestamp);

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.strcmp(pg_catalog.text, pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.strcmp(pg_catalog.text, pg_catalog.text)
RETURNS pg_catalog.int4
AS
$$
BEGIN
    if $1 = $2 then
        return 0;
    elsif $1 < $2 then
        return -1;
    else
        return 1;
    end if;
END 
$$
strict language 'plpgsql';

DROP FUNCTION IF EXISTS mysql.insert(text, int, int, text) cascade;
CREATE OR REPLACE FUNCTION mysql.insert(text, int, int, text)
RETURNS text
AS
$$
DECLARE
ret text;
start_index int;
len int;
BEGIN
    start_index = $2;
    len = $3;

    if 0 < start_index then
        if start_index <= length($1) then
            if len < 0 then
                len = length($1) + 1 - start_index;
            end if;

            ret = (select pg_catalog.overlay($1, $4, start_index, len));
        else 
            ret = $1;
        end if;
    else
        ret = $1;
    end if;

    return ret;
END 
$$
strict language 'plpgsql';

DROP FUNCTION IF EXISTS mysql.log(pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.numeric)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.log(pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.int8)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.log(pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.int4)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.log(pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.log(pg_catalog.int2)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 < $1 then
        return pg_catalog.log(2.718281828, $1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.sqrt(pg_catalog.numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.numeric)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.sqrt(pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.int8)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.sqrt(pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.int4)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.sqrt(pg_catalog.int2) cascade;
CREATE OR REPLACE FUNCTION mysql.sqrt(pg_catalog.int2)
RETURNS pg_catalog.numeric
AS 
$$
BEGIN
    if 0 <= $1 then
        return pg_catalog.sqrt($1);
    else
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.conv(pg_catalog.int8, pg_catalog.int4, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.conv(pg_catalog.int8, pg_catalog.int4, pg_catalog.int4)
RETURNS pg_catalog.text
AS 
$$
BEGIN
    if $2 = 10 then
        if $3 = 2 then
            return mysql.convert_bigint_to_varbit($1)::pg_catalog.text;
        elsif $3 = 16 then
            return to_hex($1);
        elsif $3 = 10 then
            if 0 <= $1 then
                return $1;
            else 
                raise exception 'unsupport data scope';
            end if;
        else
            raise exception 'unsupport number system';
        end if;
    else
        raise exception 'unsupport number system';
        return null;
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.is_valid_binary(text) cascade;
CREATE OR REPLACE FUNCTION mysql.is_valid_binary(text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'isValidBinary'
LANGUAGE C STRICT IMMUTABLE;

DROP FUNCTION IF EXISTS mysql.convert_text_varbit_to_bigint(text) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_text_varbit_to_bigint(text)
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'convertTextVarbitToBigint'
LANGUAGE C STRICT IMMUTABLE; 

DROP FUNCTION IF EXISTS mysql.is_valid_hex(text) cascade;
CREATE OR REPLACE FUNCTION mysql.is_valid_hex(text)
RETURNS pg_catalog.bool
AS '$libdir/mysm', 'isValidHex'
LANGUAGE C STRICT IMMUTABLE;

DROP FUNCTION IF EXISTS mysql.is_numeric(pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.is_numeric(pg_catalog.text) 
RETURNS pg_catalog.bool 
AS 
$$ 
BEGIN 
    RETURN $1 ~ '^([+-]?[0-9]+[.]?[0-9]*|[.][0-9]+)$'; 
END 
$$ 
LANGUAGE plpgsql STRICT VOLATILE;

DROP FUNCTION IF EXISTS mysql.convert_text_to_int8(text) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_text_to_int8(text)
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'convertTextToInt8'
LANGUAGE C STRICT IMMUTABLE;

DROP FUNCTION IF EXISTS mysql.convert_text_hex_to_text_varbit(text) cascade;
CREATE OR REPLACE FUNCTION mysql.convert_text_hex_to_text_varbit(text)
RETURNS pg_catalog.text
AS '$libdir/mysm', 'convertTextHexToTextVarbit'
LANGUAGE C STRICT IMMUTABLE;

DROP FUNCTION IF EXISTS mysql.conv(pg_catalog.text, pg_catalog.int4, pg_catalog.int4) cascade;
CREATE OR REPLACE FUNCTION mysql.conv(pg_catalog.text, pg_catalog.int4, pg_catalog.int4)
RETURNS pg_catalog.text
AS 
$$
DECLARE
    isValidBin pg_catalog.bool;
    isValidHex pg_catalog.bool;
    tmp pg_catalog.int8;
BEGIN
    if $2 = 2 then
        isValidBin = mysql.is_valid_binary($1);
        if isValidBin = true then
            if $3 = 2 then
                return $1;
            elsif $3 = 10 then
                tmp = mysql.convert_text_varbit_to_bigint($1);
                if tmp is not null then
                    return tmp::pg_catalog.text;
                else 
                    raise exception 'unsupport data scope';
                end if;
            elsif $3 = 16 then
                return to_hex(mysql.convert_text_varbit_to_bigint($1))::pg_catalog.text;
            else
                raise exception 'unsupport number system';
            end if;
        else
            return '0';
        end if;
    elsif $2 = 10 then
        tmp = mysql.convert_text_to_int8($1);
        if $3 = 2 then
            return mysql.convert_bigint_to_varbit(tmp)::pg_catalog.text;
        elsif $3 = 16 then
            return to_hex(tmp);
        elsif $3 = 10 then
            if 0 <= tmp then
                return tmp;
            else
                raise exception 'unsupport data scope';
            end if;
        else
            raise exception 'unsupport number system';
        end if;
    elsif $2 = 16 then
        isValidHex = mysql.is_valid_hex($1);
        if isValidHex = true then
            if $3 = 2 then
                return mysql.convert_text_hex_to_text_varbit($1);
            elsif $3 = 10 then
                tmp = mysql.convert_text_varbit_to_bigint(mysql.convert_text_hex_to_text_varbit($1));
                if tmp is not null then
                    return tmp::pg_catalog.text;
                else
                    raise exception 'unsupport data scope';
                end if;
            elsif $3 = 16 then
                return $1;
            else
                raise exception 'unsupport number system';
            end if;
        else 
            return '0';
        end if;
    else
        raise exception 'unsupport number system';
    end if;
END
$$
STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.bit_count(pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_count(pg_catalog.text) 
RETURNS pg_catalog.int4
AS
$$
BEGIN
    -- for bit_count(NULL)
    return null;
END
$$
VOLATILE STRICT LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.bit_count(pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_count(pg_catalog.int8) 
RETURNS pg_catalog.int4
AS
$$
DECLARE
num pg_catalog.int4;
BEGIN
    num = pg_catalog.bit_count($1::pg_catalog.bit(64));
    return num;
END
$$
VOLATILE STRICT LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.bit_count(pg_catalog.bytea) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_count(pg_catalog.bytea) 
RETURNS pg_catalog.int4
AS
$$
BEGIN
    return mysql.bit_count($1::pg_catalog.int8);
END
$$
VOLATILE STRICT LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.bit_or_varbit(pg_catalog.int8, pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_or_varbit(pg_catalog.int8, pg_catalog.varbit)
RETURNS pg_catalog.int8
AS 
$$
DECLARE
tmp pg_catalog.int8;
BEGIN
    if $1 is not null then
        tmp = $1 | ($2::pg_catalog.int8);
    else
        tmp = $2::pg_catalog.int8;
    end if;
    return tmp;
END
$$
LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.bit_or_varbit_final(pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_or_varbit_final(pg_catalog.int8)
RETURNS pg_catalog.int8
AS 
$$
BEGIN
    return $1;
END
$$
LANGUAGE 'plpgsql';

DROP AGGREGATE IF EXISTS mysql.bit_or(pg_catalog.varbit) cascade;
CREATE AGGREGATE mysql.bit_or(pg_catalog.varbit) (
    SFUNC=mysql.bit_or_varbit,
    STYPE=pg_catalog.int8,
    FINALFUNC=mysql.bit_or_varbit_final
);

DROP FUNCTION IF EXISTS mysql.bit_and_varbit(pg_catalog.int8, pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_and_varbit(pg_catalog.int8, pg_catalog.varbit)
RETURNS pg_catalog.int8
AS 
$$
DECLARE
tmp pg_catalog.int8;
BEGIN
    if $1 is not null then
        tmp = $1 & ($2::pg_catalog.int8);
    else
        tmp = $2::pg_catalog.int8;
    end if;
    return tmp;
END
$$
LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.bit_and_varbit_final(pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_and_varbit_final(pg_catalog.int8)
RETURNS pg_catalog.int8
AS 
$$
BEGIN
    return $1;
END
$$
LANGUAGE 'plpgsql';

DROP AGGREGATE IF EXISTS mysql.bit_and(pg_catalog.varbit) cascade;
CREATE AGGREGATE mysql.bit_and(pg_catalog.varbit) (
    SFUNC=mysql.bit_and_varbit,
    STYPE=pg_catalog.int8,
    FINALFUNC=mysql.bit_and_varbit_final
);

DROP FUNCTION IF EXISTS mysql.bit_xor_varbit(pg_catalog.int8, pg_catalog.varbit) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_xor_varbit(pg_catalog.int8, pg_catalog.varbit)
RETURNS pg_catalog.int8
AS 
$$
DECLARE
tmp pg_catalog.int8;
BEGIN
    if $1 is not null then
        tmp = $1 ^ ($2::pg_catalog.int8);
    else
        tmp = $2::pg_catalog.int8;
    end if;
    return tmp;
END
$$
LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.bit_xor_varbit_final(pg_catalog.int8) cascade;
CREATE OR REPLACE FUNCTION mysql.bit_xor_varbit_final(pg_catalog.int8)
RETURNS pg_catalog.int8
AS 
$$
BEGIN
    return $1;
END
$$
LANGUAGE 'plpgsql';

DROP AGGREGATE IF EXISTS mysql.bit_xor(pg_catalog.varbit) cascade;
CREATE AGGREGATE mysql.bit_xor(pg_catalog.varbit) (
    SFUNC=mysql.bit_xor_varbit,
    STYPE=pg_catalog.int8,
    FINALFUNC=mysql.bit_xor_varbit_final
);

DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.tinyint, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.smallint, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition int, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition bigint, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition pg_catalog.bool, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition float, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition mysql.double, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition numeric, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition text, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition time, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition date, value2 timestamp, value3 timestamp) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.tinyint, value3 mysql.tinyint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.smallint, value3 mysql.smallint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.mediumint, value3 mysql.mediumint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 int, value3 int) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 bigint, value3 bigint) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 float4, value3 float4) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 float8, value3 float8) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 numeric, value3 numeric) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.double, value3 mysql.double) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.real, value3 mysql.real) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 char, value3 char) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 varchar, value3 varchar) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 text, value3 text) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 date, value3 date) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 time, value3 time) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 mysql.datetime, value3 mysql.datetime) cascade;
DROP FUNCTION IF EXISTS mysql.if(condition timestamp, value2 timestamp, value3 timestamp) cascade;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.tinyint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.smallint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition int, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition bigint, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.bool, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition float, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition mysql.double, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 int, value3 int)
RETURNS int
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 float4, value3 float4)
RETURNS float4
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 float8, value3 float8)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 char, value3 char)
RETURNS char
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 text, value3 text)
RETURNS text
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 date, value3 date)
RETURNS date
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 time, value3 time)
RETURNS time
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition numeric, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
BEGIN
    if condition != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition text, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_text_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition time, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_time_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition date, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_date_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.tinyint, value3 mysql.tinyint)
RETURNS mysql.tinyint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.smallint, value3 mysql.smallint)
RETURNS mysql.smallint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.mediumint, value3 mysql.mediumint)
RETURNS mysql.mediumint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 int, value3 int)
RETURNS int
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 bigint, value3 bigint)
RETURNS bigint
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 float4, value3 float4)
RETURNS float4
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 float8, value3 float8)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 numeric, value3 numeric)
RETURNS numeric
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.double, value3 mysql.double)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.real, value3 mysql.real)
RETURNS float8
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 char, value3 char)
RETURNS char
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 varchar, value3 varchar)
RETURNS varchar
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 text, value3 text)
RETURNS text
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 date, value3 date)
RETURNS date
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 time, value3 time)
RETURNS time
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 mysql.datetime, value3 mysql.datetime)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.if(condition timestamp, value2 timestamp, value3 timestamp)
RETURNS timestamp
AS
$$
DECLARE
    tmp float8;
BEGIN
    tmp = mysql.convert_timestamp_to_float8($1);
    if tmp != 0 then
        return value2;
    else
        return value3;
    end if;
END;           
$$
IMMUTABLE LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION pg_read_file(text, bigint, bigint, boolean) TO public;
GRANT EXECUTE ON FUNCTION pg_read_file(text, bigint, bigint) TO public; 
GRANT EXECUTE ON FUNCTION pg_read_file(text) TO public;
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text, bigint, bigint, boolean) TO public;
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text, bigint, bigint) TO public; 
GRANT EXECUTE ON FUNCTION pg_read_binary_file(text) TO public;

drop function if exists mysql.load_file(text) cascade;
create or replace function mysql.load_file(text)
returns text
AS
$$
BEGIN
    --pg_read_file只能读取PGDATA下的文件。
    return pg_catalog.pg_read_file($1);
END;
$$
immutable strict language 'plpgsql'; 

DROP FUNCTION IF EXISTS period_diff(integer, integer) cascade;
DROP FUNCTION IF EXISTS mysql.period_diff(integer, integer) cascade;
CREATE OR REPLACE FUNCTION mysql.period_diff(integer, integer)
RETURNS integer
AS
$$
DECLARE
    arg1 text;
    arg2 text;
    baseyear integer;
    period1 text;
    period2 text;
    months1 integer;
    months2 integer;
BEGIN
    arg1 = $1::text;
    arg2 = $2::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period1 := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period1 := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period1 := arg1;
    END IF;

    IF pg_catalog.length(period1) = 4 THEN
        baseyear := SUBSTRING(period1 FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        months1 := baseyear * 12 + SUBSTRING(period1 FROM 3)::integer;
    ELSIF pg_catalog.length(period1) = 6 THEN
        months1 := SUBSTRING(period1 FROM 1 FOR 4)::integer * 12 + SUBSTRING(period1 FROM 5)::integer;
    ELSE
        RETURN NULL;
    END IF;

    IF pg_catalog.length(arg2) < 4 THEN
        period2 := pg_catalog.lpad(arg2, 4, 0);
    ELSIF pg_catalog.length(arg2) = 5 THEN
        period2 := pg_catalog.lpad(arg2, 6, 0);
    ELSE
        period2 := arg2;
    END IF;

    IF pg_catalog.length(period2) = 4 THEN
        baseyear := SUBSTRING(period2 FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        months2 := baseyear * 12 + SUBSTRING(period2 FROM 3)::integer;
    ELSIF pg_catalog.length(period2) = 6 THEN
        months2 := SUBSTRING(period2 FROM 1 FOR 4)::integer * 12 + SUBSTRING(period2 FROM 5)::integer;
    ELSE
        RETURN NULL;
    END IF;

    RETURN months1 - months2;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS period_add(integer, integer) cascade;
DROP FUNCTION IF EXISTS mysql.period_add(integer, integer) cascade;
CREATE OR REPLACE FUNCTION mysql.period_add(integer, integer)
RETURNS text
AS
$$
DECLARE
    arg1 text;
    period text;
    base date;
    baseyear integer;
BEGIN
    arg1 = $1::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period := arg1;
    END IF;

    IF pg_catalog.length(period) = 4 THEN
        baseyear := substring(period FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        base := (baseyear operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 3) operator(pg_catalog.||) '-01')::date;
    ELSIF pg_catalog.length(period) = 6 THEN
        base := (SUBSTRING(period FROM 1 FOR 4) operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 5) operator(pg_catalog.||) '-01')::date;
    ELSE
        RETURN NULL;
    END IF;

    base := base + ('1 month'::pg_catalog.interval * $2);
    RETURN pg_catalog.lpad(extract(year from base)::text, 4, '0') operator(pg_catalog.||) pg_catalog.lpad(extract(month from base)::text, 2, '0');
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS mysql.unix_timestamp(text) cascade;
CREATE OR REPLACE FUNCTION mysql.unix_timestamp(text)
RETURNS decimal
AS
$$
DECLARE
    fin_str text := $1;
    rt decimal;
BEGIN
    -- rt := extract(epoch from fin_str::timestamp(6))-28800;
    rt := extract(epoch from fin_str::timestamp(6)::timestamptz(6));

    RETURN rt;
END
$$
immutable LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.unix_timestamp(numeric);
CREATE OR REPLACE FUNCTION mysql.unix_timestamp(numeric)
RETURNS decimal
AS
$$
DECLARE
    fin_str text;
    rt decimal;
BEGIN
    fin_str := mysql._convert_format_to_halo_for_number_datetime($1::text);
    -- rt := extract(epoch from fin_str::timestamp(6))-28800;
    rt := extract(epoch from fin_str::timestamp(6)::timestamptz(6));

    RETURN rt;
END
$$
immutable LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.date(numeric) cascade;
CREATE OR REPLACE FUNCTION mysql.date(numeric)
RETURNS date
AS
$$
DECLARE
    fin_str text;
    rt date;
BEGIN
    fin_str := mysql._convert_format_to_halo_for_number_datetime($1::text);
    rt := (select fin_str::date);

    RETURN rt;
END
$$
immutable LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS mysql.utc_date() cascade;
CREATE OR REPLACE FUNCTION mysql.utc_date()
RETURNS date
AS
$$
    SELECT (CURRENT_TIMESTAMP::pg_catalog.timestamptz AT TIME ZONE 'UTC')::date
$$
immutable LANGUAGE SQL;

DROP FUNCTION IF EXISTS mysql.utc_time() cascade;
CREATE OR REPLACE FUNCTION mysql.utc_time()
RETURNS time
AS
$$
    SELECT (CURRENT_TIMESTAMP::pg_catalog.timestamptz AT TIME ZONE 'UTC')::time(0)
$$
immutable LANGUAGE SQL;

DROP FUNCTION IF EXISTS mysql.utc_time(in prec int) cascade;
CREATE OR REPLACE FUNCTION mysql.utc_time(in prec int)
RETURNS time
AS
$$
DECLARE
    tmp time(6);
    ret time(6);
BEGIN
    tmp = (SELECT (CURRENT_TIMESTAMP(6)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::time(6));
    if prec = 0 then
        ret = tmp::time(0);
    elsif prec = 1 then
        ret = tmp::time(1);
    elsif prec = 2 then
        ret = tmp::time(2);
    elsif prec = 3 then
        ret = tmp::time(3);
    elsif prec = 4 then
        ret = tmp::time(4);
    elsif prec = 5 then
        ret = tmp::time(5);
    elsif prec = 6 then
        ret = tmp::time(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''utc_time''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
immutable language 'plpgsql';

DROP FUNCTION IF EXISTS mysql.utc_timestamp() cascade;
CREATE OR REPLACE FUNCTION mysql.utc_timestamp()
RETURNS timestamp
AS
$$
    SELECT (CURRENT_TIMESTAMP::pg_catalog.timestamptz AT TIME ZONE 'UTC')::timestamp(0)
$$
immutable LANGUAGE SQL;

DROP FUNCTION IF EXISTS mysql.utc_timestamp(in prec int) cascade;
CREATE OR REPLACE FUNCTION mysql.utc_timestamp(in prec int)
RETURNS timestamp
AS
$$
DECLARE
    tmp timestamp(6);
    ret timestamp(6);
BEGIN
    tmp = (SELECT (CURRENT_TIMESTAMP(6)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::timestamp(6));
    if prec = 0 then
        ret = tmp::timestamp(0);
    elsif prec = 1 then
        ret = tmp::timestamp(1);
    elsif prec = 2 then
        ret = tmp::timestamp(2);
    elsif prec = 3 then
        ret = tmp::timestamp(3);
    elsif prec = 4 then
        ret = tmp::timestamp(4);
    elsif prec = 5 then
        ret = tmp::timestamp(5);
    elsif prec = 6 then
        ret = tmp::timestamp(6);
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''utc_timestamp''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
immutable language 'plpgsql';

DROP FUNCTION IF EXISTS mysql.curtime(in prec int) cascade;
CREATE OR REPLACE FUNCTION mysql.curtime(in prec int)
RETURNS time
AS
$$
DECLARE
    ret time(6);
BEGIN
    if prec = 0 then
        ret = (select current_time(0));
    elsif prec = 1 then
        ret = (select current_time(1));
    elsif prec = 2 then
        ret = (select current_time(2));
    elsif prec = 3 then
        ret = (select current_time(3));
    elsif prec = 4 then
        ret = (select current_time(4));
    elsif prec = 5 then
        ret = (select current_time(5));
    elsif prec = 6 then
        ret = (select current_time(6));
    elsif prec < 0 then
        raise exception 'You have an error in your SQL syntax;';
    else
        raise exception 'Too-big precision % specified for ''curtime''. Maximum is 6.', prec;
    end if;

    return ret;
END
$$
immutable language 'plpgsql';

DROP FUNCTION IF EXISTS mysql.last_insert_id() cascade;
CREATE OR REPLACE FUNCTION mysql.last_insert_id()
RETURNS pg_catalog.int8
AS '$libdir/mysm', 'mysLastInsertId'
LANGUAGE C STRICT VOLATILE;

DROP FUNCTION IF EXISTS mysql.amend_def_val_for_internal(pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.amend_def_val_for_internal(pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    tmp pg_catalog.int4;
BEGIN
    tmp := 0;
    tmp := position('nextval' in $1);
    if 1 = tmp then
        ret = $1;
    else
        tmp := 0;
        tmp := position('::' in $1);
        if 0 < tmp then
            ret = substring($1 from 2 for (tmp - 3));
            if lower(ret) = 'null' then
                ret = null;
            end if;
        else
            ret = $1;
        end if;
    end if;
    return ret;
END
$$
strict language 'plpgsql';

DROP FUNCTION IF EXISTS mysql.get_column_key(pg_catalog.text, pg_catalog.text, pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.get_column_key(pg_catalog.text, pg_catalog.text, pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
declare
    ret pg_catalog.text;
    schemaName pg_catalog.varchar(128);
    tableName pg_catalog.varchar(128);
    columnName pg_catalog.varchar(128);
    indexs RECORD;
    columnNums pg_catalog.varchar(1024);
    columnIndexNum pg_catalog.int4;
BEGIN
    schemaName := $1;
    tableName := $2;
    columnName := $3;

    ret := '';

    FOR indexs IN
        select cl.relname, ind.indrelid, ind.indkey, ind.indnatts,
                ind.indnkeyatts, ind.indisunique, ind.indisprimary
            from pg_class cl, pg_index ind
            where (cl.oid = ind.indexrelid) and
                    (ind.indrelid = (select oid
                                        from pg_class
                                        where (relname = tableName) and
                                                (relnamespace = (select oid
                                                                    from pg_namespace
                                                                    where nspname = schemaName))))
    LOOP
        columnNums := replace(indexs.indkey::pg_catalog.text,
                                ' '::pg_catalog.text,
                                ','::pg_catalog.text);
        execute format('select count(*)
                            from pg_attribute
                            where (attrelid = %s) and (attnum in (%s)) and (attname = \'%s\')',
                       indexs.indrelid, columnNums, columnName)
            into columnIndexNum;
        if (1 <= columnIndexNum) then
            if (indexs.indisprimary = 1) then
                ret := "PRI";
                exit;
            else
                if (indexs.indisunique = 1) then
                    if (1 = array_length(string_to_array(indexs.indkey::text, ' '), 1)) then
                        ret := "UNI";
                        exit;
                    else
                        ret := "MUL";
                    end if;
                else
                    ret := "MUL";
                end if;
            end if;
        end if;
    END LOOP;

    return ret;
END;
$$
IMMUTABLE STRICT LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.get_column_extra(pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.get_column_extra(pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
declare
    ret pg_catalog.text;
BEGIN
    ret := '';

    if (($1 is not null) and (0 < position('nextval(' in $1))) then
        ret := "auto_increment";
    end if;

    return ret;
END;
$$
IMMUTABLE LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS mysql.get_proc_def(funcName text,
                                           proallargtypes oid[],
                                           proargmodes "char"[],
                                           proargnames text[],
                                           prosrc text) cascade;
CREATE OR REPLACE FUNCTION mysql.get_proc_def(funcName text,
                                              proallargtypes oid[],
                                              proargmodes "char"[],
                                              proargnames text[],
                                              prosrc text)
RETURNS text
AS
$$
DECLARE
    ret text;
    allArgNum int;
    argIndex int;
BEGIN
    ret := "CREATE PROCEDURE";

    ret := ret || " ";
    ret := ret || funcName;

    ret := ret || "(";
    if (proallargtypes is not null) then
        allArgNum := array_length(proallargtypes, 1);
        argIndex := 1;
        LOOP
            if (1 < argIndex) then
                ret := ret || ",";
            end if;

            if (proargmodes[argIndex] = 'i') then
                ret := ret || " IN";
            else
                ret := ret || " OUT";
            end if;

            ret := ret || " ";
            ret := ret || proargnames[argIndex];

            ret := ret || " ";
            ret := ret || proallargtypes[argIndex]::regType::text;

            argIndex := argIndex + 1;
            EXIT WHEN argIndex > allArgNum;
        END LOOP;
    end if;
    ret := ret || ")\n";

    ret := ret || prosrc;

    RETURN ret;
END
$$
IMMUTABLE LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS mysql.to_days(pg_catalog.text);
CREATE OR REPLACE FUNCTION mysql.to_days(pg_catalog.text)
RETURNS integer
LANGUAGE sql
IMMUTABLE STRICT
AS
$function$
    SELECT ($1::date - '2000-01-01'::date) + 730485
$function$;

DROP FUNCTION IF EXISTS mysql.to_days(timestamp without time zone);
CREATE OR REPLACE FUNCTION mysql.to_days(timestamp without time zone)
RETURNS integer
LANGUAGE sql
IMMUTABLE STRICT
AS
$function$
    SELECT ($1::date - '2000-01-01'::date) + 730485
$function$;

CREATE OR REPLACE FUNCTION mysql.uuid_short()
RETURNS pg_catalog.text
AS '$libdir/mysm', 'uuidShort'
LANGUAGE C VOLATILE;

CREATE OR REPLACE FUNCTION mysql.isnull(pg_catalog.int2)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        return true;
    else
        return false;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.isnull(pg_catalog.bool)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is null) then
        return true;
    else
        return false;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ifnull(pg_catalog.varchar, pg_catalog.int8)
RETURNS pg_catalog.varchar
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2::pg_catalog.varchar;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ifnull(pg_catalog.int8, pg_catalog.varchar)
RETURNS pg_catalog.varchar
AS
$$
BEGIN
    if $1 is not null then
        return $1::pg_catalog.varchar;
    else
        return $2;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.ifnull(pg_catalog.text, pg_catalog.int8)
RETURNS pg_catalog.text
AS
$$
BEGIN
    if $1 is not null then
        return $1;
    else
        return $2::pg_catalog.text;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.timestampadd(text, integer, timestamp without time zone)
RETURNS timestamp without time zone
AS
$$
    --SELECT $3 + ($2 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $1)::pg_catalog.interval
    SELECT $3 + pg_catalog.concat($2, ' ', $1)::pg_catalog.interval
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.date_format(timestamptz, text)
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
                WHEN n =# 'a' THEN pg_catalog.to_char($1, 'Dy')
                WHEN n =# 'b' THEN pg_catalog.to_char($1, 'Mon')
                WHEN n =# 'c' THEN pg_catalog.to_char($1, 'FMMM')
                WHEN n =# 'D' THEN pg_catalog.to_char($1, 'FMDDth')
                WHEN n =# 'd' THEN pg_catalog.to_char($1, 'DD')
                WHEN n =# 'e' THEN pg_catalog.to_char($1, 'FMDD')
                WHEN n =# 'f' THEN pg_catalog.to_char($1, 'US')
                WHEN n =# 'H' THEN pg_catalog.to_char($1, 'HH24')
                WHEN n =# 'h' THEN pg_catalog.to_char($1, 'HH12')
                WHEN n =# 'I' THEN pg_catalog.to_char($1, 'HH12')
                WHEN n =# 'i' THEN pg_catalog.to_char($1, 'MI')
                WHEN n =# 'j' THEN pg_catalog.to_char($1, 'DDD')
                WHEN n =# 'k' THEN pg_catalog.to_char($1, 'FMHH24')
                WHEN n =# 'l' THEN pg_catalog.to_char($1, 'FMHH12')
                WHEN n =# 'M' THEN pg_catalog.to_char($1, 'FMMonth')
                WHEN n =# 'm' THEN pg_catalog.to_char($1, 'MM')
                WHEN n =# 'p' THEN pg_catalog.to_char($1, 'AM')
                WHEN n =# 'r' THEN pg_catalog.to_char($1, 'HH12:MI:SS AM')
                WHEN n =# 'S' THEN pg_catalog.to_char($1, 'SS')
                WHEN n =# 's' THEN pg_catalog.to_char($1, 'SS')
                WHEN n =# 'T' THEN pg_catalog.to_char($1, 'HH24:MI:SS')
                WHEN n =# 'U' THEN pg_catalog.lpad(week($1::date, 0)::text, 2, '0')
                WHEN n =# 'u' THEN pg_catalog.lpad(week($1::date, 1)::text, 2, '0')
                WHEN n =# 'V' THEN pg_catalog.lpad(week($1::date, 2)::text, 2, '0')
                WHEN n =# 'v' THEN pg_catalog.lpad(week($1::date, 3)::text, 2, '0')
                WHEN n =# 'W' THEN pg_catalog.to_char($1, 'FMDay')
                WHEN n =# 'w' THEN EXTRACT(DOW FROM $1)::text
                WHEN n =# 'X' THEN pg_catalog.lpad(((_calc_week($1::date, _week_mode(2)))[2])::text, 4, '0')
                WHEN n =# 'x' THEN pg_catalog.lpad(((_calc_week($1::date, _week_mode(3)))[2])::text, 4, '0')
                WHEN n =# 'Y' THEN pg_catalog.to_char($1, 'YYYY')
                WHEN n =# 'y' THEN pg_catalog.to_char($1, 'YY')
                WHEN n =# '%' THEN pg_catalog.to_char($1, '%')
                ELSE NULL
            END;

            if res is not null then
                --temp := temp operator(pg_catalog.||) res;
                temp := pg_catalog.concat(temp, res);
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            --temp := temp operator(pg_catalog.||) c;
            temp := pg_catalog.concat(temp, c);
            i := i + 1;
        END IF;
    END LOOP;
    RETURN temp;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.time_format(pg_catalog.interval, text)
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
        -- Look at current character
        c := substring($2 FROM i FOR 1);
        -- If it's a '%' and not the last character then process it as a placeholder
        IF c = '%' AND i != len THEN
            n := (substring($2 FROM (i + 1) FOR 1))::character;
            SELECT INTO res CASE
            WHEN n =# 'a' THEN '0'
            WHEN n =# 'b' THEN '0'
            WHEN n =# 'c' THEN '0'
            WHEN n =# 'D' THEN '0'
            WHEN n =# 'd' THEN '0'
            WHEN n =# 'e' THEN '0'
            WHEN n =# 'f' THEN pg_catalog.to_char($1, 'US')
            WHEN n =# 'H' THEN pg_catalog.to_char($1, 'HH24')
            WHEN n =# 'h' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'I' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'i' THEN pg_catalog.to_char($1, 'MI')
            WHEN n =# 'j' THEN '0'
            WHEN n =# 'k' THEN pg_catalog.to_char($1, 'FMHH24')
            WHEN n =# 'l' THEN (pg_catalog.to_char($1, 'FMHH12')::integer % 12)::text
            WHEN n =# 'M' THEN '0'
            WHEN n =# 'm' THEN '0'
            WHEN n =# 'p' THEN pg_catalog.to_char($1, 'AM')
            --WHEN n =# 'r' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            --    operator(pg_catalog.||)
            --    pg_catalog.to_char($1, ':MI:SS ')
            --    operator(pg_catalog.||)
            --    CASE WHEN pg_catalog.to_char($1, 'FMHH24')::integer <= 11 THEN 'AM' ELSE 'PM' END
            WHEN n =# 'r' THEN pg_catalog.concat(
                pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0'),
                pg_catalog.to_char($1, ':MI:SS '),
                (CASE WHEN pg_catalog.to_char($1, 'FMHH24')::integer <= 11 THEN 'AM' ELSE 'PM' END))
            WHEN n =# 'S' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 's' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 'T' THEN pg_catalog.to_char($1, 'HH24:MI:SS')
            WHEN n =# 'U' THEN '0'
            WHEN n =# 'u' THEN '0'
            WHEN n =# 'V' THEN '0'
            WHEN n =# 'v' THEN '0'
            WHEN n =# 'W' THEN '0'
            WHEN n =# 'w' THEN '0'
            WHEN n =# 'X' THEN '0'
            WHEN n =# 'x' THEN '0'
            WHEN n =# 'Y' THEN '0'
            WHEN n =# 'y' THEN '0'
            WHEN n =# '%' THEN pg_catalog.to_char($1, '%')
            ELSE NULL
            END;
            if res is not null then
                --temp := temp operator(pg_catalog.||) res;
                temp := pg_catalog.concat(temp, res);
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            -- Otherwise just append the character to the string
            --temp = temp operator(pg_catalog.||) c;
            temp := pg_catalog.concat(temp, c);
            i := i + 1;
        END IF;
    END LOOP;
    RETURN temp;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.str_to_date(text, text)
RETURNS timestamp without time zone
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
            WHEN n =# 'a' THEN 'Dy'
            WHEN n =# 'b' THEN 'Mon'
            WHEN n =# 'c' THEN 'FMMM'
            WHEN n =# 'D' THEN 'FMDDth'
            WHEN n =# 'd' THEN 'DD'
            WHEN n =# 'e' THEN 'FMDD'
            WHEN n =# 'f' THEN 'US'
            WHEN n =# 'H' THEN 'HH24'
            WHEN n =# 'h' THEN 'HH12'
            WHEN n =# 'I' THEN 'HH12'
            WHEN n =# 'i' THEN 'MI'
            WHEN n =# 'j' THEN 'DDD'
            WHEN n =# 'k' THEN 'FMHH24'
            WHEN n =# 'l' THEN 'FMHH12'
            WHEN n =# 'M' THEN 'FMMonth'
            WHEN n =# 'm' THEN 'MM'
            WHEN n =# 'p' THEN 'AM'
            WHEN n =# 'r' THEN 'HH12:MI:SS AM'
            WHEN n =# 'S' THEN 'SS'
            WHEN n =# 's' THEN 'SS'
            WHEN n =# 'T' THEN 'HH24:MI:SS'
            WHEN n =# 'U' THEN '?'
            WHEN n =# 'u' THEN '?'
            WHEN n =# 'V' THEN '?'
            WHEN n =# 'v' THEN '?'
            WHEN n =# 'W' THEN 'FMDay'
            WHEN n =# 'w' THEN '?'
            WHEN n =# 'X' THEN '?'
            WHEN n =# 'x' THEN '?'
            WHEN n =# 'Y' THEN 'YYYY'
            WHEN n =# 'y' THEN 'YY'
            WHEN n =# '%' THEN '%'
            ELSE NULL
            END;
            if res is not null then
                --temp := temp operator(pg_catalog.||) res;
                temp := pg_catalog.concat(temp, res);
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            --temp = temp operator(pg_catalog.||) c;
            temp := pg_catalog.concat(temp, c);
            i := i + 1;
        END IF;
    END LOOP;

    RETURN pg_catalog.to_timestamp($1, temp)::timestamp without time zone;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.makedate(integer, integer)
RETURNS date
AS
$$
    select
        CASE WHEN $2 > 0 THEN
            --(($1 operator(pg_catalog.||) '-01-01')::date + ($2 - 1) * '1 day'::pg_catalog.interval)::date
            (pg_catalog.concat($1, '-01-01')::date + ($2 - 1) * '1 day'::pg_catalog.interval)::date
        ELSE
            NULL
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.maketime(integer, integer, integer)
RETURNS pg_catalog.interval
AS
$$
    --select ($1 operator(pg_catalog.||) ':' operator(pg_catalog.||) $2 operator(pg_catalog.||) ':' operator(pg_catalog.||) $3)::pg_catalog.interval
    select pg_catalog.concat($1, ':', $2, ':', $3)::pg_catalog.interval
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_tz(timestamp, text, text)
RETURNS timestamp
AS
$$
    SELECT
        CASE WHEN POSITION(':' IN $3) = 0 THEN
            --($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp with time zone AT TIME ZONE $3
            pg_catalog.concat($1, ' ', $2)::timestamp with time zone AT TIME ZONE $3
        ELSE
            --($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp with time zone AT TIME ZONE $3::pg_catalog.interval
            pg_catalog.concat($1, ' ', $2)::timestamp with time zone AT TIME ZONE $3::pg_catalog.interval
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_to_time_format(text)
RETURNS pg_catalog.interval
AS
$$
DECLARE
    tmp text;
    len int;
    colon_index int;
    pot_index int;
    c char;
    i int;
BEGIN
    tmp = $1;
    len = pg_catalog.length(tmp);
    colon_index = position(':' in tmp);
    pot_index = position('.' in tmp);

    if 0 < colon_index then
        return $1::pg_catalog.interval;
    else
        if pot_index = 0 then
            i = len;
        else
            i = pot_index - 1;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                i = i - 2;
            else
                return null;
            end if;
        elsif i = 2 then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                return $1::pg_catalog.interval;
            else
                return null;
            end if;
        else
            return $1::pg_catalog.interval;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        elsif 2 = i then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                --tmp = '00:' operator(pg_catalog.||) tmp;
                tmp = pg_catalog.concat('00:', tmp);
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        else
            --tmp = '00:0' operator(pg_catalog.||) tmp;
            tmp = pg_catalog.concat('00:0', tmp);
            return tmp::pg_catalog.interval;
        end if;
    end if;
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.last_day(date)
RETURNS date
AS
$$
    SELECT CASE WHEN EXTRACT(MONTH FROM $1) = 12 THEN
                --(((extract(year from $1) + 1) operator(pg_catalog.||) '-01-01')::date - '1 day'::pg_catalog.interval)::date
                (pg_catalog.concat((extract(year from $1) + 1), '-01-01')::date - '1 day'::pg_catalog.interval)::date
           ELSE
                --((extract(year from $1) operator(pg_catalog.||) '-' operator(pg_catalog.||) (extract(month from $1) + 1) operator(pg_catalog.||) '-01')::date - '1 day'::pg_catalog.interval)::date
                (pg_catalog.concat(extract(year from $1), '-', (extract(month from $1) + 1), '-01')::date - '1 day'::pg_catalog.interval)::date
           END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION period_add(integer, integer)
RETURNS text
AS
$$
DECLARE
    arg1 text;
    period text;
    base date;
    baseyear integer;
BEGIN
    arg1 = $1::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period := arg1;
    END IF;

    IF pg_catalog.length(period) = 4 THEN
        baseyear := substring(period FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        --base := (baseyear operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 3) operator(pg_catalog.||) '-01')::date;
        base := pg_catalog.concat(baseyear, '-', SUBSTRING(period FROM 3), '-01')::date;
    ELSIF pg_catalog.length(period) = 6 THEN
    --base := (SUBSTRING(period FROM 1 FOR 4) operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 5) operator(pg_catalog.||) '-01')::date;
    base := pg_catalog.concat(SUBSTRING(period FROM 1 FOR 4), '-', SUBSTRING(period FROM 5), '-01')::date;
    ELSE
        RETURN NULL;
    END IF;

    base := base + ('1 month'::pg_catalog.interval * $2);
    RETURN pg_catalog.lpad(extract(year from base)::text, 4, '0') operator(pg_catalog.||) pg_catalog.lpad(extract(month from base)::text, 2, '0');
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.timestampadd(text, integer, timestamp without time zone)
RETURNS timestamp without time zone
AS
$$
DECLARE
    result timestamp(6);
BEGIN
    if $1 = 'quarter' then
        --SELECT $3 + ($2 operator(pg_catalog.||) ' month')::pg_catalog.interval * 3 into result;
        SELECT $3 + pg_catalog.concat($2, ' month')::pg_catalog.interval * 3 into result;
    else
        --SELECT $3 + ($2 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $1)::pg_catalog.interval into result;
        SELECT $3 + pg_catalog.concat($2, ' ', $1)::pg_catalog.interval into result;
    end if;

    return result;
END
$$
IMMUTABLE STRICT LANGUAGE plpgsql;

drop function if exists mysql.time_format(pg_catalog.interval, text);
CREATE OR REPLACE FUNCTION mysql.time_format(time, text)
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
        -- Look at current character
        c := substring($2 FROM i FOR 1);
        -- If it's a '%' and not the last character then process it as a placeholder
        IF c = '%' AND i != len THEN
            n := (substring($2 FROM (i + 1) FOR 1))::character;
            SELECT INTO res CASE
            WHEN n =# 'a' THEN '0'
            WHEN n =# 'b' THEN '0'
            WHEN n =# 'c' THEN '0'
            WHEN n =# 'D' THEN '0'
            WHEN n =# 'd' THEN '00'
            WHEN n =# 'e' THEN '0'
            WHEN n =# 'f' THEN pg_catalog.to_char($1, 'US')
            WHEN n =# 'H' THEN pg_catalog.to_char($1, 'HH24')
            WHEN n =# 'h' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'I' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            WHEN n =# 'i' THEN pg_catalog.to_char($1, 'MI')
            WHEN n =# 'j' THEN '0'
            WHEN n =# 'k' THEN pg_catalog.to_char($1, 'FMHH24')
            WHEN n =# 'l' THEN (pg_catalog.to_char($1, 'FMHH12')::integer % 12)::text
            WHEN n =# 'M' THEN '0'
            WHEN n =# 'm' THEN '00'
            WHEN n =# 'p' THEN pg_catalog.to_char($1, 'AM')
            --WHEN n =# 'r' THEN pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0')
            --    operator(pg_catalog.||)
            --    pg_catalog.to_char($1, ':MI:SS ')
            --    operator(pg_catalog.||)
            --    CASE WHEN pg_catalog.to_char($1, 'FMHH24')::integer <= 11 THEN 'AM' ELSE 'PM' END
            WHEN n =# 'r' THEN pg_catalog.concat(
                pg_catalog.lpad((pg_catalog.to_char($1, 'HH12')::integer % 12)::text, 2, '0'),
                pg_catalog.to_char($1, ':MI:SS '),
                CASE WHEN pg_catalog.to_char($1, 'FMHH24')::integer <= 11 THEN 'AM' ELSE 'PM' END)
            WHEN n =# 'S' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 's' THEN pg_catalog.to_char($1, 'SS')
            WHEN n =# 'T' THEN pg_catalog.to_char($1, 'HH24:MI:SS')
            WHEN n =# 'U' THEN '0'
            WHEN n =# 'u' THEN '0'
            WHEN n =# 'V' THEN '0'
            WHEN n =# 'v' THEN '0'
            WHEN n =# 'W' THEN '0'
            WHEN n =# 'w' THEN '0'
            WHEN n =# 'X' THEN '0'
            WHEN n =# 'x' THEN '0'
            WHEN n =# 'Y' THEN '0000'
            WHEN n =# 'y' THEN '00'
            WHEN n =# '%' THEN pg_catalog.to_char($1, '%')
            ELSE NULL
            END;
            if res is not null then
                --temp := temp operator(pg_catalog.||) res;
                temp := pg_catalog.concat(temp, res);
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            -- Otherwise just append the character to the string
            --temp = temp operator(pg_catalog.||) c;
            temp := pg_catalog.concat(temp, c);
            i := i + 1;
        END IF;
    END LOOP;
    RETURN temp;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.makedate(integer, integer)
RETURNS date
AS
$$
    select
        CASE WHEN $2 > 0 THEN
            --(($1 operator(pg_catalog.||) '-01-01')::date + ($2 - 1) * '1 day'::pg_catalog.interval)::date
            (pg_catalog.concat($1, '-01-01')::date + ($2 - 1) * '1 day'::pg_catalog.interval)::date
        ELSE
            NULL
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

drop function if exists mysql.maketime(integer, integer, integer);
CREATE OR REPLACE FUNCTION mysql.maketime(integer, integer, numeric)
RETURNS time
AS
$$
    --select ($1 operator(pg_catalog.||) ':' operator(pg_catalog.||) $2 operator(pg_catalog.||) ':' operator(pg_catalog.||) $3)::time(6)
    select pg_catalog.concat($1, ':', $2, ':', $3)::time(6)
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_tz(timestamp, text, text)
RETURNS timestamp
AS
$$
    SELECT
        CASE WHEN POSITION(':' IN $3) = 0 THEN
            --($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp(6) with time zone AT TIME ZONE $3
            pg_catalog.concat($1, ' ', $2)::timestamp(6) with time zone AT TIME ZONE $3
        ELSE
            --($1 operator(pg_catalog.||) ' ' operator(pg_catalog.||) $2)::timestamp(6) with time zone AT TIME ZONE $3::pg_catalog.interval
            pg_catalog.concat($1, ' ', $2)::timestamp(6) with time zone AT TIME ZONE $3::pg_catalog.interval
        END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION mysql.convert_to_time_format(text)
RETURNS pg_catalog.interval
AS
$$
DECLARE
    tmp text;
    len int;
    colon_index int;
    pot_index int;
    c char;
    i int;
BEGIN
    tmp = $1;
    len = pg_catalog.length(tmp);
    colon_index = position(':' in tmp);
    pot_index = position('.' in tmp);

    if 0 < colon_index then
        return $1::pg_catalog.interval;
    else
        if pot_index = 0 then
            i = len;
        else
            i = pot_index - 1;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                i = i - 2;
            else
                return null;
            end if;
        elsif i = 2 then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                return $1::pg_catalog.interval;
            else
                return null;
            end if;
        else
            return $1::pg_catalog.interval;
        end if;

        if 2 < i then
            c = pg_catalog.substring(tmp, (i - 1), 1);
            if c <= '5' then
                tmp = (select pg_catalog.overlay(tmp, ':', (i - 1), 0));
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        elsif 2 = i then
            c = pg_catalog.substring(tmp, 1, 1);
            if c <= '5' then
                --tmp = '00:' operator(pg_catalog.||) tmp;
                tmp = pg_catalog.concat('00:', tmp);
                return tmp::pg_catalog.interval;
            else
                return null;
            end if;
        else
            --tmp = '00:0' operator(pg_catalog.||) tmp;
            tmp = pg_catalog.concat('00:0', tmp);
            return tmp::pg_catalog.interval;
        end if;
    end if;
EXCEPTION
    WHEN others THEN
        return null;
END;
$$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.last_day(date)
RETURNS date
AS
$$
    SELECT CASE WHEN EXTRACT(MONTH FROM $1) = 12 THEN
                --(((extract(year from $1) + 1) operator(pg_catalog.||) '-01-01')::date - '1 day'::pg_catalog.interval)::date
                (pg_catalog.concat((extract(year from $1) + 1), '-01-01')::date - '1 day'::pg_catalog.interval)::date
           ELSE
                --((extract(year from $1) operator(pg_catalog.||) '-' operator(pg_catalog.||) (extract(month from $1) + 1) operator(pg_catalog.||) '-01')::date - '1 day'::pg_catalog.interval)::date
                (pg_catalog.concat(extract(year from $1), '-', (extract(month from $1) + 1), '-01')::date - '1 day'::pg_catalog.interval)::date
           END
$$
IMMUTABLE STRICT LANGUAGE SQL;

CREATE OR REPLACE FUNCTION period_add(integer, integer)
RETURNS text
AS
$$
DECLARE
    arg1 text;
    period text;
    base date;
    baseyear integer;
BEGIN
    arg1 = $1::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period := arg1;
    END IF;

    IF pg_catalog.length(period) = 4 THEN
        baseyear := substring(period FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        --base := (baseyear operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 3) operator(pg_catalog.||) '-01')::date;
        base := pg_catalog.concat(baseyear, '-', SUBSTRING(period FROM 3), '-01')::date;
    ELSIF pg_catalog.length(period) = 6 THEN
    --base := (SUBSTRING(period FROM 1 FOR 4) operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 5) operator(pg_catalog.||) '-01')::date;
    base := pg_catalog.concat(SUBSTRING(period FROM 1 FOR 4), '-', SUBSTRING(period FROM 5), '-01')::date;
    ELSE
        RETURN NULL;
    END IF;

    base := base + ('1 month'::pg_catalog.interval * $2);
    --RETURN pg_catalog.lpad(extract(year from base)::text, 4, '0') operator(pg_catalog.||) pg_catalog.lpad(extract(month from base)::text, 2, '0');
    RETURN pg_catalog.concat(pg_catalog.lpad(extract(year from base)::text, 4, '0'), pg_catalog.lpad(extract(month from base)::text, 2, '0'));
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.text_or_anynoarray(pg_catalog.text, pg_catalog.anynonarray)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is not null) then
        --return $1 operator(pg_catalog.||) $2;
        return pg_catalog.concat($1, $2);
    else
        if $2::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
        return 0::pg_catalog.int8 operator(mysql.||) $2::pg_catalog.int8;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.anynonarray_or_text(pg_catalog.anynonarray, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($2 is not null) then
        --return $1 operator(pg_catalog.||) $2;
        return pg_catalog.concat($1, $2);
    else
        if $1::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.text_or_anynoarray(pg_catalog.text, pg_catalog.anynonarray)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($1 is not null) then
        --return $1 operator(pg_catalog.||) $2;
        return pg_catalog.concat($1, $2);
    else
        if $2::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
        return 0::pg_catalog.int8 operator(mysql.||) $2::pg_catalog.int8;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.anynonarray_or_text(pg_catalog.anynonarray, pg_catalog.text)
returns pg_catalog.bool
AS
$$
BEGIN
    if ($2 is not null) then
        --return $1 operator(pg_catalog.||) $2;
        return pg_catalog.concat($1, $2);
    else
        if $1::pg_catalog.int8 != 0 then
            return true;
        else
            return null;
        end if;
    end if;
END;
$$
immutable language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.period_add(integer, integer)
RETURNS text
AS
$$
DECLARE
    arg1 text;
    period text;
    base date;
    baseyear integer;
BEGIN
    arg1 = $1::text;

    IF pg_catalog.length(arg1) < 4 THEN
        period := pg_catalog.lpad(arg1, 4, 0);
    ELSIF pg_catalog.length(arg1) = 5 THEN
        period := pg_catalog.lpad(arg1, 6, 0);
    ELSE
        period := arg1;
    END IF;

    IF pg_catalog.length(period) = 4 THEN
        baseyear := substring(period FROM 1 FOR 2);
        IF baseyear BETWEEN 70 AND 99 THEN
            baseyear := baseyear + 1900;
        ELSE
            baseyear := baseyear + 2000;
        END IF;
        --base := (baseyear operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 3) operator(pg_catalog.||) '-01')::date;
        base := pg_catalog.concat(baseyear, '-', SUBSTRING(period FROM 3), '-01')::date;
    ELSIF pg_catalog.length(period) = 6 THEN
        --base := (SUBSTRING(period FROM 1 FOR 4) operator(pg_catalog.||) '-' operator(pg_catalog.||) SUBSTRING(period FROM 5) operator(pg_catalog.||) '-01')::date;
        base := pg_catalog.concat(SUBSTRING(period FROM 1 FOR 4), '-', SUBSTRING(period FROM 5), '-01')::date;
    ELSE
        RETURN NULL;
    END IF;

    base := base + ('1 month'::pg_catalog.interval * $2);
    --RETURN pg_catalog.lpad(extract(year from base)::text, 4, '0') operator(pg_catalog.||) pg_catalog.lpad(extract(month from base)::text, 2, '0');
    RETURN pg_catalog.concat(pg_catalog.lpad(extract(year from base)::text, 4, '0'), pg_catalog.lpad(extract(month from base)::text, 2, '0'));
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS mysql.get_column_extra(pg_catalog.text) cascade;
CREATE OR REPLACE FUNCTION mysql.get_column_extra(pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
declare
    ret pg_catalog.text;
BEGIN
    ret := '';

    if (($1 is not null) and (0 < position('nextval(' in $1))) then
        ret := "auto_increment";
    end if;

    return ret;
END;
$$
IMMUTABLE LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mysql.amend_def_val_for_internal(pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    tmp pg_catalog.int4;
BEGIN
    tmp := 0;
    tmp := position('nextval' in $1);
    if 1 = tmp then
        ret = $1;
    else
        tmp := 0;
        tmp := position('::' in $1);
        if 0 < tmp then
            ret = substring($1 from 1 for (tmp - 1));
            if lower(ret) = 'null' then
                ret = null;
            end if;
        else
            ret = $1;
        end if;
    end if;
    return ret;
END
$$
strict language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.array_to_string_for_mysql(anyarray, text)
RETURNS text
AS
$$
DECLARE
    ret text;
    x text;
    sep_count int;
    null_count int;
    array_index int;
BEGIN
    ret = '';
    sep_count = 0;
    null_count = 0;
    array_index = 0;

    if $1 is not null then
        foreach x in array $1
        loop
            if x is NULL then
                null_count = null_count + 1;
            elsif length(x) = 0 then
                if 0 < sep_count then
                    --ret = ret || $2;
                    ret := pg_catalog.concat(ret, $2);
                end if;
                sep_count = sep_count + 1;

                --ret = ret || '';
                ret := pg_catalog.concat(ret, '');
            else
                if 0 < sep_count then
                    --ret = ret || $2;
                    ret := pg_catalog.concat(ret, $2);
                end if;
                sep_count = sep_count + 1;

                --ret = ret || x;
                ret := pg_catalog.concat(ret, x);
            end if;

            array_index = array_index + 1;
        end loop;

        if array_index <= null_count then
            ret = NULL;
        end if;
    else
        ret = NULL;
    end if;

    return ret;
end
$$
language 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.elt(VARIADIC pg_catalog.any)
RETURNS pg_catalog.text
AS '$libdir/mysm', 'elt'
IMMUTABLE LANGUAGE C;

CREATE OR REPLACE FUNCTION mysql.space(pg_catalog.int4)
RETURNS text
AS
$$
DECLARE
    ret pg_catalog.text;
BEGIN
    ret := '';

    IF (1 <= $1) THEN
        FOR i IN 1..$1 LOOP
            ret := ret operator(pg_catalog.||) ' ';
        END LOOP;
    ELSE
        ret := '';
    END IF;

    return ret;
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.log2(double precision)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if ($1 != 0) then
        return pg_catalog.log(2, $1::pg_catalog.numeric);
    else
        return null;
    end if;
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.log2(pg_catalog.numeric)
RETURNS pg_catalog.numeric
AS
$$
BEGIN
    if ($1 != 0) then
        return pg_catalog.log(2, $1);
    else
        return null;
    end if;
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.addtime(timestamp, pg_catalog.float8)
RETURNS pg_catalog.timestamp
AS
$$
BEGIN
    return mysql.addtime($1, $2::text);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.addtime(time, pg_catalog.float8)
RETURNS pg_catalog.time
AS
$$
BEGIN
    return mysql.addtime($1, $2::text);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.addtime(pg_catalog.text, pg_catalog.float8)
RETURNS pg_catalog.text
AS
$$
BEGIN
    return mysql.addtime($1, $2::text);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.subtime(timestamp, pg_catalog.float8)
RETURNS pg_catalog.timestamp
AS
$$
BEGIN
    return mysql.subtime($1, $2::text);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.subtime(time, pg_catalog.float8)
RETURNS pg_catalog.time
AS
$$
BEGIN
    return mysql.subtime($1, $2::text);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.subtime(pg_catalog.text, pg_catalog.float8)
RETURNS pg_catalog.text
AS
$$
BEGIN
    return mysql.subtime($1, $2::text);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

create or replace function mysql."extract"(text, text)
returns numeric
AS
$$
BEGIN
    return mysql.`extract`($1, $2::timestamp);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.timestampdiff(unit text, ts1 text, ts2 text)
RETURNS bigint
AS
$$
BEGIN
    return mysql.timestampdiff($1, $2::pg_catalog.timestamp, $3::pg_catalog.timestamp);
END
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.str_to_date(text, text)
RETURNS timestamp without time zone
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
    if ((pg_catalog.length($1) < 8) || (pg_catalog.length($2) < 6)) then
        return null;
    end if;

    WHILE i <= len LOOP
        c := substring($2 FROM i FOR 1);
        IF c = '%' AND i != len THEN
            n := (substring($2 FROM (i + 1) FOR 1))::character;
            SELECT INTO res CASE
            WHEN n =# 'a' THEN 'Dy'
            WHEN n =# 'b' THEN 'Mon'
            WHEN n =# 'c' THEN 'FMMM'
            WHEN n =# 'D' THEN 'FMDDth'
            WHEN n =# 'd' THEN 'DD'
            WHEN n =# 'e' THEN 'FMDD'
            WHEN n =# 'f' THEN 'US'
            WHEN n =# 'H' THEN 'HH24'
            WHEN n =# 'h' THEN 'HH12'
            WHEN n =# 'I' THEN 'HH12'
            WHEN n =# 'i' THEN 'MI'
            WHEN n =# 'j' THEN 'DDD'
            WHEN n =# 'k' THEN 'FMHH24'
            WHEN n =# 'l' THEN 'FMHH12'
            WHEN n =# 'M' THEN 'FMMonth'
            WHEN n =# 'm' THEN 'MM'
            WHEN n =# 'p' THEN 'AM'
            WHEN n =# 'r' THEN 'HH12:MI:SS AM'
            WHEN n =# 'S' THEN 'SS'
            WHEN n =# 's' THEN 'SS'
            WHEN n =# 'T' THEN 'HH24:MI:SS'
            WHEN n =# 'U' THEN '?'
            WHEN n =# 'u' THEN '?'
            WHEN n =# 'V' THEN '?'
            WHEN n =# 'v' THEN '?'
            WHEN n =# 'W' THEN 'FMDay'
            WHEN n =# 'w' THEN '?'
            WHEN n =# 'X' THEN '?'
            WHEN n =# 'x' THEN '?'
            WHEN n =# 'Y' THEN 'YYYY'
            WHEN n =# 'y' THEN 'YY'
            WHEN n =# '%' THEN '%'
            ELSE NULL
            END;
            if res is not null then
                --temp := temp operator(pg_catalog.||) res;
                temp := pg_catalog.concat(temp, res);
                i := i + 2;
            else
                i := i + 1;
            end if;
        ELSE
            --temp = temp operator(pg_catalog.||) c;
            temp := pg_catalog.concat(temp, c);
            i := i + 1;
        END IF;
    END LOOP;

    RETURN pg_catalog.to_timestamp($1, temp)::timestamp without time zone;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.timestamp(text, text)
RETURNS timestamp without time zone
AS
$$
DECLARE
    ts pg_catalog.timestamp;
    tm pg_catalog.time;
BEGIN
    ts := $1::pg_catalog.timestamp;
    tm := $2::pg_catalog.time;
    return ts + tm;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.bin(pg_catalog.int8)
RETURNS pg_catalog.text
AS
$$
BEGIN
    return mysql.cast_bigint_to_varbit($1)::text;
END
$$
IMMUTABLE STRICT LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.sum_bool(bigint, pg_catalog.bool)
RETURNS bigint
AS
$$
BEGIN
    if $2 is not null then
        if $1 is not null then
            return $1 + $2::bigint;
        else
            return $2::bigint;
        end if;
    else
        return $1;
    end if;
END
$$
LANGUAGE plpgsql;

create or replace aggregate mysql.sum(pg_catalog.bool) (
    SFUNC=mysql.sum_bool,
    STYPE=bigint
);

CREATE OR REPLACE FUNCTION mysql.datediff(timestamp without time zone, text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
    SELECT $1::date - $2::date
$function$;

CREATE OR REPLACE FUNCTION mysql.datediff(text, timestamp without time zone)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
    SELECT $1::date - $2::date
$function$;

CREATE OR REPLACE FUNCTION mysql.DATE_FORMAT(text, text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
    SELECT mysql.DATE_FORMAT($1::timestamp without time zone, $2)
$function$;

CREATE OR REPLACE FUNCTION mysql.text_avg_accum(internal, pg_catalog.text)
RETURNS internal
AS '$libdir/mysm', 'textAvgAccum'
LANGUAGE C;

create or replace aggregate mysql.avg(pg_catalog.text) (
    SFUNC=mysql.text_avg_accum,
    STYPE=pg_catalog.internal,
    FINALFUNC=pg_catalog.numeric_avg
);

create or replace function mysql.format(pg_catalog.numeric, pg_catalog.int8)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
BEGIN
    ret := '';

    ret := (pg_catalog.round($1, $2::pg_catalog.int4))::pg_catalog.text;

    return ret;
END;
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

create or replace function mysql.export_set(pg_catalog.int8, pg_catalog.text, pg_catalog.text, pg_catalog.text, pg_catalog.int8)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    binStr pg_catalog.text;
    binStrLen pg_catalog.int4;
    tmp pg_catalog.text;
BEGIN
    ret := '';

    binStr := mysql.cast_bigint_to_varbit($1)::pg_catalog.text;
    binStr := pg_catalog.lpad(binStr, $5::pg_catalog.int4, '0');
    binStr := pg_catalog.reverse(binStr);
    binStrLen := pg_catalog.length(binStr);
    for ind in 1..binStrLen loop
        if (1 < ind) then
            ret := ret operator(pg_catalog.||) $4;
        end if;

        tmp := pg_catalog.substring(binStr, ind, 1);
        if (tmp = '1') then
            ret := ret operator(pg_catalog.||) $2;
        else
            ret := ret operator(pg_catalog.||) $3;
        end if;
    end loop;

    return ret;
END;
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION mysql.make_set(pg_catalog.int8, VARIADIC pg_catalog.text[])
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    binStr pg_catalog.text;
    binStrLen pg_catalog.int4;
    setItemCount pg_catalog.int4;
    retItemCount pg_catalog.int4;
    tmp pg_catalog.text;
BEGIN
    ret := '';

    binStr := mysql.cast_bigint_to_varbit($1)::pg_catalog.text;
    binStr := pg_catalog.reverse(binStr);
    binStrLen := pg_catalog.length(binStr);
    setItemCount := array_length($2, 1);
    if (binStrLen < setItemCount) then
        retItemCount := binStrLen;
    else
        retItemCount := setItemCount;
    end if;
    for i in 1..retItemCount loop
        tmp := pg_catalog.substring(binStr, i, 1);
        if ((tmp = '1') and ($2[i] is not null)) then
            if (1 < i) then
                ret := ret operator(pg_catalog.||) ',';
            end if;
            ret := ret operator(pg_catalog.||) $2[i];
        end if;
    end loop;

    return ret;
END;
$$
IMMUTABLE STRICT LANGUAGE 'plpgsql';


GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mysql TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mys_informa_schema TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA sys TO public;
GRANT ALL PRIVILEGES ON ALL tables IN SCHEMA mys_sys TO public;


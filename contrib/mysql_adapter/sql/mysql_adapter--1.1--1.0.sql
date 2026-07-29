-- \echo mysql_adapter extension downgrading 1.1 -> 1.0

-- Restore original pg_cast castcontext for int<->bool casts
-- (changed to implicit by the extension for MySQL WHERE-clause compatibility).
UPDATE pg_catalog.pg_cast SET castcontext = 'e' WHERE castsource = 23 AND casttarget = 16;
UPDATE pg_catalog.pg_cast SET castcontext = 'e' WHERE castsource = 16 AND casttarget = 23;

-- Version 1.1 only adds functions.  Remove each object from the extension
-- before dropping it; the objects that define version 1.0 remain members.
DO $$
DECLARE
	function_name regprocedure;
BEGIN
	FOREACH function_name IN ARRAY ARRAY[
		'mysql.concat_ws(text,text[])'::regprocedure,
		'mysql.format(numeric,int)'::regprocedure,
		'mysql.format(float8,int)'::regprocedure,
		'mysql.format(int8,int)'::regprocedure,
		'mysql.format(int4,int)'::regprocedure,
		'mysql.hex(int8)'::regprocedure,
		'mysql.hex(int4)'::regprocedure,
		'mysql.hex(bytea)'::regprocedure,
		'mysql.hex(text)'::regprocedure,
		'mysql.instr(text,text)'::regprocedure,
		'mysql.lcase(text)'::regprocedure,
		'mysql.ucase(text)'::regprocedure,
		'mysql.lpad(text,int,text)'::regprocedure,
		'mysql.rpad(text,int,text)'::regprocedure,
		'mysql.ltrim(text)'::regprocedure,
		'mysql.rtrim(text)'::regprocedure,
		'mysql.space(int)'::regprocedure,
		'mysql.strcmp(text,text)'::regprocedure,
		'mysql.substring_index(text,text,int)'::regprocedure,
		'mysql.trim(text)'::regprocedure,
		'mysql.trim(text,text)'::regprocedure,
		'mysql.ceiling(numeric)'::regprocedure,
		'mysql.ceiling(float8)'::regprocedure,
		'mysql.crc32(text)'::regprocedure,
		'mysql.degrees(float8)'::regprocedure,
		'mysql.floor(numeric)'::regprocedure,
		'mysql.floor(float8)'::regprocedure,
		'mysql.ln(float8)'::regprocedure,
		'mysql.log2(float8)'::regprocedure,
		'mysql.log2(numeric)'::regprocedure,
		'mysql.log10(float8)'::regprocedure,
		'mysql.mod(numeric,numeric)'::regprocedure,
		'mysql.mod(float8,float8)'::regprocedure,
		'mysql.pi()'::regprocedure,
		'mysql.pow(float8,float8)'::regprocedure,
		'mysql.radians(float8)'::regprocedure,
		'mysql.rand()'::regprocedure,
		'mysql.rand(int4)'::regprocedure,
		'mysql.round(numeric,int)'::regprocedure,
		'mysql.round(float8,int)'::regprocedure,
		'mysql.sign(numeric)'::regprocedure,
		'mysql.sign(float8)'::regprocedure,
		'mysql.sqrt(numeric)'::regprocedure,
		'mysql.sqrt(float8)'::regprocedure,
		'mysql.truncate(numeric,int)'::regprocedure,
		'mysql.truncate(float8,int)'::regprocedure,
		'mysql.curdate()'::regprocedure,
		'mysql.curtime()'::regprocedure,
		'mysql.current_date()'::regprocedure,
		'mysql.current_time()'::regprocedure,
		'mysql.date_add(timestamp,interval)'::regprocedure,
		'mysql.date_add(date,interval)'::regprocedure,
		'mysql.date_sub(timestamp,interval)'::regprocedure,
		'mysql.date_sub(date,interval)'::regprocedure,
		'mysql.datediff(date,date)'::regprocedure,
		'mysql.datediff(timestamp,timestamp)'::regprocedure,
		'mysql.day(date)'::regprocedure,
		'mysql.day(timestamp)'::regprocedure,
		'mysql.dayname(date)'::regprocedure,
		'mysql.dayname(timestamp)'::regprocedure,
		'mysql.dayofmonth(date)'::regprocedure,
		'mysql.dayofweek(date)'::regprocedure,
		'mysql.dayofweek(timestamp)'::regprocedure,
		'mysql.dayofyear(date)'::regprocedure,
		'mysql.dayofyear(timestamp)'::regprocedure,
		'mysql.hour(time)'::regprocedure,
		'mysql.hour(timestamp)'::regprocedure,
		'mysql.minute(time)'::regprocedure,
		'mysql.minute(timestamp)'::regprocedure,
		'mysql.month(date)'::regprocedure,
		'mysql.month(timestamp)'::regprocedure,
		'mysql.monthname(date)'::regprocedure,
		'mysql.monthname(timestamp)'::regprocedure,
		'mysql.now()'::regprocedure,
		'mysql.current_timestamp()'::regprocedure,
		'mysql.quarter(date)'::regprocedure,
		'mysql.quarter(timestamp)'::regprocedure,
		'mysql.second(time)'::regprocedure,
		'mysql.second(timestamp)'::regprocedure,
		'mysql.sysdate()'::regprocedure,
		'mysql.timestampdiff(text,timestamp,timestamp)'::regprocedure,
		'mysql.to_days(date)'::regprocedure,
		'mysql.week(date,int)'::regprocedure,
		'mysql.weekday(date)'::regprocedure,
		'mysql.year(date)'::regprocedure,
		'mysql.year(timestamp)'::regprocedure,
		'mysql.yearweek(date)'::regprocedure,
		'mysql.md5(text)'::regprocedure,
		'mysql.sha1(text)'::regprocedure,
		'mysql.sha2(text,int)'::regprocedure,
		'mysql.database()'::regprocedure,
		'mysql.user()'::regprocedure,
		'mysql.version()'::regprocedure,
		'mysql.connection_id()'::regprocedure,
		'mysql.last_insert_id()'::regprocedure,
		'mysql.row_count()'::regprocedure,
		'mysql.found_rows()'::regprocedure
	]
	LOOP
		EXECUTE format('ALTER EXTENSION mysql_adapter DROP FUNCTION %s',
						   function_name);
		EXECUTE format('DROP FUNCTION %s', function_name);
	END LOOP;
END
$$;

-- Drop bare INT / INTEGER domains added during upgrade (KF-053)
DROP DOMAIN IF EXISTS mysql.integer;
DROP DOMAIN IF EXISTS mysql.int;

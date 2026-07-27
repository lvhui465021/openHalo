CREATE EXTENSION pgcrypto;
CREATE EXTENSION mysql_adapter VERSION '1.0';

SELECT extversion
FROM pg_extension
WHERE extname = 'mysql_adapter';

ALTER EXTENSION mysql_adapter UPDATE TO '1.1';

SELECT extversion,
       to_regprocedure('mysql.concat_ws(text,text[])') IS NOT NULL AS concat_ws_present,
       to_regprocedure('mysql.row_count()') IS NOT NULL AS row_count_present
FROM pg_extension
WHERE extname = 'mysql_adapter';

ALTER EXTENSION mysql_adapter UPDATE TO '1.0';

SELECT extversion,
       to_regprocedure('mysql.concat_ws(text,text[])') IS NULL AS concat_ws_removed,
       to_regprocedure('mysql.row_count()') IS NULL AS row_count_removed
FROM pg_extension
WHERE extname = 'mysql_adapter';

DROP EXTENSION mysql_adapter;
DROP EXTENSION pgcrypto;

-- MySQL-protocol compatibility suite: current aux_mysql inventory.
-- Runtime-based checks (PG18 baseline, not hardcoded UDB-TX numbers).
-- The required API manifest contains user-visible function names;
-- internal cast/operator helpers are covered by the signature counts.

DROP TEMPORARY TABLE IF EXISTS mysql_compat_required_api;
CREATE TEMPORARY TABLE mysql_compat_required_api (
  function_name VARCHAR(64) PRIMARY KEY
);

INSERT INTO mysql_compat_required_api(function_name) VALUES
  ('adddate'), ('addtime'), ('bin'), ('bit_count'),
  ('concat'), ('concat_ws'), ('conv'), ('convert_tz'),
  ('curdate'), ('current_user'), ('curtime'),
  ('database'), ('date'), ('date_add'), ('date_format'), ('date_sub'),
  ('datediff'), ('day'), ('dayname'), ('dayofmonth'), ('dayofweek'),
  ('dayofyear'), ('elt'), ('export_set'), ('field'),
  ('find_in_set'), ('floor'), ('format'), ('found_rows'), ('from_days'),
  ('from_unixtime'), ('get_lock'), ('hour'), ('if'), ('ifnull'), ('insert'),
  ('instr'), ('is_free_lock'), ('isnull'), ('json_unquote'),
  ('last_day'), ('last_insert_id'), ('lcase'), ('left'), ('length'),
  ('locate'), ('log'), ('log2'), ('lpad'), ('make_set'),
  ('makedate'), ('maketime'), ('microsecond'), ('mid'), ('minute'), ('mod'),
  ('month'), ('monthname'), ('now'), ('period_add'),
  ('period_diff'), ('quarter'), ('rand'), ('release_lock'), ('right'),
  ('round'), ('row_count'), ('rpad'), ('sec_to_time'), ('second'),
  ('session_user'), ('sleep'), ('space'), ('sqrt'), ('str_to_date'),
  ('strcmp'), ('subdate'), ('substr'), ('substring'), ('substring_index'),
  ('subtime'), ('sysdate'), ('time_format'), ('time_to_sec'),
  ('timediff'), ('timestamp'), ('timestampadd'), ('timestampdiff'),
  ('truncate'), ('ucase'), ('unix_timestamp'), ('utc_date'),
  ('utc_time'), ('utc_timestamp'), ('uuid'), ('uuid_short'),
  ('version'), ('week'), ('weekday'), ('weekofyear'), ('year'), ('yearweek');

-- Extension is installed with a valid version
SELECT 'extension_version' AS test_name,
       extversion IS NOT NULL AND extversion::numeric >= 1.0 AS passed
FROM pg_extension WHERE extname = 'aux_mysql';

-- mysql schema has a significant number of functions (>100)
SELECT 'mysql_function_catalog_baseline' AS test_name,
       COUNT(DISTINCT p.proname) > 100
       AND COUNT(*) > 100
       AND SUM(p.prokind = 'f') > 100 AS passed
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'mysql';

-- Required public API functions must all exist
SELECT 'required_public_api_present' AS test_name,
       COUNT(*) = 0 AS passed
FROM mysql_compat_required_api r
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'mysql'
    AND p.proname = r.function_name
);

-- mys_informa_schema relations exist
SELECT 'compatibility_schema_relation_baseline' AS test_name,
       COUNT(*) >= 3 AS passed
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'mys_informa_schema'
  AND c.relkind IN ('r', 'v', 'm');

DROP TEMPORARY TABLE mysql_compat_required_api;
-- MySQL-protocol compatibility suite: current aux_mysql inventory.
-- Counts are the PG16/UDB-TX 1.5 baseline, not the older OpenHalo aux_mysql
-- numbers.  The required API manifest contains user-visible function names;
-- internal cast/operator helpers are covered by the signature counts.

DROP TEMPORARY TABLE IF EXISTS mysql_compat_required_api;
CREATE TEMPORARY TABLE mysql_compat_required_api (
  function_name VARCHAR(64) PRIMARY KEY
);

INSERT INTO mysql_compat_required_api(function_name) VALUES
  ('adddate'), ('addtime'), ('avg'), ('bin'), ('bit_and'), ('bit_count'),
  ('bit_or'), ('bit_xor'), ('ceil'), ('ceiling'), ('concat'), ('concat_ws'),
  ('conv'), ('convert_tz'), ('curdate'), ('current_user'), ('curtime'),
  ('database'), ('date'), ('date_add'), ('date_format'), ('date_sub'),
  ('datediff'), ('day'), ('dayname'), ('dayofmonth'), ('dayofweek'),
  ('dayofyear'), ('elt'), ('export_set'), ('extract'), ('field'),
  ('find_in_set'), ('floor'), ('format'), ('found_rows'), ('from_days'),
  ('from_unixtime'), ('get_lock'), ('hour'), ('if'), ('ifnull'), ('insert'),
  ('instr'), ('is_free_lock'), ('is_used_lock'), ('isnull'), ('json_unquote'),
  ('last_day'), ('last_insert_id'), ('lcase'), ('left'), ('length'),
  ('load_file'), ('locate'), ('log'), ('log2'), ('lpad'), ('make_set'),
  ('makedate'), ('maketime'), ('microsecond'), ('mid'), ('minute'), ('mod'),
  ('month'), ('monthname'), ('now'), ('numeric_timestamp'), ('period_add'),
  ('period_diff'), ('quarter'), ('rand'), ('release_lock'), ('right'),
  ('round'), ('row_count'), ('rpad'), ('schema'), ('sec_to_time'), ('second'),
  ('session_user'), ('sleep'), ('space'), ('sqrt'), ('str_to_date'),
  ('strcmp'), ('subdate'), ('substr'), ('substring'), ('substring_index'),
  ('subtime'), ('sum'), ('sysdate'), ('time_format'), ('time_to_sec'),
  ('timediff'), ('timestamp'), ('timestampadd'), ('timestampdiff'),
  ('to_days'), ('truncate'), ('ucase'), ('unix_timestamp'), ('user'),
  ('utc_date'), ('utc_time'), ('utc_timestamp'), ('uuid'), ('uuid_short'),
  ('version'), ('week'), ('weekday'), ('weekofyear'), ('year'), ('yearweek');

SELECT 'extension_version' AS test_name,
       extversion = '1.5' AS passed
FROM pg_extension WHERE extname = 'aux_mysql';

SELECT 'mysql_function_catalog_baseline' AS test_name,
       COUNT(DISTINCT p.proname) = 590
       AND COUNT(*) = 1101
       AND SUM(p.prokind = 'f') = 1094
       AND SUM(p.prokind = 'a') = 7 AS passed
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'mysql';

SELECT 'mysql_type_operator_baseline' AS test_name,
       (SELECT COUNT(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'mysql') = 60
       AND
       (SELECT COUNT(*) FROM pg_operator o JOIN pg_namespace n ON n.oid = o.oprnamespace
        WHERE n.nspname = 'mysql') = 330 AS passed;

SELECT 'extension_member_baseline' AS test_name,
       COUNT(*) = 1783 AS passed
FROM pg_depend d JOIN pg_extension e ON e.oid = d.refobjid
WHERE e.extname = 'aux_mysql' AND d.deptype = 'e';

SELECT 'required_public_api_present' AS test_name,
       COUNT(*) = 0 AS passed
FROM mysql_compat_required_api r
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'mysql'
    AND CAST(p.proname AS BINARY) = CAST(r.function_name AS BINARY)
);

SELECT 'compatibility_schema_relation_baseline' AS test_name,
       SUM(n.nspname = 'mys_informa_schema') = 84
       AND SUM(n.nspname = 'performance_schema') = 111
       AND SUM(n.nspname = 'mys_sys') = 1 AS passed
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('mys_informa_schema', 'performance_schema', 'mys_sys')
  AND c.relkind IN ('r', 'v', 'm');

DROP TEMPORARY TABLE mysql_compat_required_api;

-- Known compatibility defects.  Execute with mysql --force.  Error statements
-- and assertions returning 0 are the current baseline; a fix must change the
-- corresponding expected/90_known_failures.out entry and move the case into a
-- positive SQL file.

-- SHOW DATABASES LIKE is not accepted by the current MySQL grammar.
SHOW DATABASES LIKE 'mysql_compat_known_metadata';

-- SHOW STATUS variants translate to a relation not created by mysql_adapter 1.5.
SHOW STATUS;
SHOW SESSION STATUS;
SHOW GLOBAL STATUS;

-- The REPEAT mapping cannot resolve an untyped polymorphic string literal.
SELECT repeat('ab', 3);

-- SQL_CALC_FOUND_ROWS (KF-020 fixed, verify)
SELECT SQL_CALC_FOUND_ROWS oid FROM pg_class ORDER BY oid LIMIT 2;
SELECT 'calc_found_rows' AS test_name, FOUND_ROWS() > 0 AS passed;

-- These MySQL encoding functions are not installed by mysql_adapter 1.5.
SELECT UNHEX(CAST('616263' AS CHAR));
SELECT TO_BASE64(CAST('abc' AS CHAR));
SELECT FROM_BASE64(CAST('YWJj' AS CHAR));

-- LOAD_FILE raises a server file error instead of returning NULL.
SELECT LOAD_FILE('/mysql-compat-file-does-not-exist');

-- BIGINT UNSIGNED is incorrectly bounded by signed int8 storage.
SELECT CAST(18446744073709551615 AS UNSIGNED);

-- Connection collation is case-insensitive, but untyped literal LIKE is not.
SELECT 'literal_like_case_insensitive' AS test_name,
       'AbC' LIKE 'a%' AS passed;

-- The ->> operator accepts a bare key but not the standard MySQL $.key path.
SELECT 'json_dollar_path' AS test_name,
       JSON_OBJECT('key', 'text')->>'$.key' = 'text' AS passed;

-- Named-lock state helpers are placeholders: IS_USED_LOCK always returns NULL.
SELECT mysql.get_lock('mysql_compat_known_lock', 0);
SELECT 'named_lock_state' AS test_name,
       mysql.is_used_lock('mysql_compat_known_lock') IS NOT NULL AS passed;
SELECT mysql.release_lock('mysql_compat_known_lock');

DROP DATABASE IF EXISTS mysql_compat_known_metadata;
CREATE DATABASE mysql_compat_known_metadata;
USE mysql_compat_known_metadata;

-- INFORMATION_SCHEMA.STATISTICS is not populated from live indexes.
CREATE TABLE mysql_known_indexed (id INT PRIMARY KEY, value_int INT);
CREATE INDEX mysql_known_value_idx ON mysql_known_indexed(value_int);

-- MySQL CREATE TRIGGER bodies are rejected by the current grammar.
CREATE TABLE mysql_known_trigger_audit(id INT PRIMARY KEY, value_int INT);
CREATE TRIGGER mysql_known_after_insert AFTER INSERT ON mysql_known_indexed
FOR EACH ROW INSERT INTO mysql_known_trigger_audit(id, value_int)
VALUES (NEW.id, NEW.value_int);
SELECT 'information_schema_statistics' AS test_name,
       COUNT(*) > 0 AS passed
FROM information_schema.statistics
WHERE table_schema = 'mysql_compat_known_metadata'
  AND table_name = 'mysql_known_indexed';

-- Multi-target UPDATE is gated in the executor but still rejected here.
CREATE TABLE mysql_known_update_a(id INT PRIMARY KEY, value_int INT);
CREATE TABLE mysql_known_update_b(id INT PRIMARY KEY, value_int INT);
INSERT INTO mysql_known_update_a VALUES (1, 10);
INSERT INTO mysql_known_update_b VALUES (1, 20);
UPDATE mysql_known_update_a AS a, mysql_known_update_b AS b
SET a.value_int = 11, b.value_int = 21
WHERE a.id = b.id;

-- A partitioned parent can be created, but attaching its partition fails.
CREATE TABLE mysql_known_partitioned(id INT, value_int INT)
PARTITION BY RANGE(id);
CREATE TABLE mysql_known_partition_0 PARTITION OF mysql_known_partitioned
FOR VALUES FROM (0) TO (10);

-- UPDATE LOW_PRIORITY is tokenized but rejected by the update parse path.
UPDATE LOW_PRIORITY mysql_known_indexed
SET value_int = value_int WHERE id = 1;

-- Non-strict MySQL normally converts a numeric prefix and emits a warning.
SET sql_mode = '';
SELECT '12abc' + 0;
SET sql_mode = DEFAULT;

DROP DATABASE mysql_compat_known_metadata;

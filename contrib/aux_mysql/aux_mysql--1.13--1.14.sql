/* contrib/aux_mysql/aux_mysql--1.13--1.14.sql */

-- MySQL CHARSET(str) builtin: returns the character set of its argument.
-- openHalo sessions are UTF-8, so text/character arguments report 'utf8'
-- (the MySQL corpus expectation); bytea reports 'binary'.
CREATE OR REPLACE FUNCTION mysql.charset(character)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE WHEN $1 IS NULL THEN NULL ELSE 'utf8' END $$;

CREATE OR REPLACE FUNCTION mysql.charset(text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE WHEN $1 IS NULL THEN NULL ELSE 'utf8' END $$;

CREATE OR REPLACE FUNCTION mysql.charset(bytea)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE WHEN $1 IS NULL THEN NULL ELSE 'binary' END $$;

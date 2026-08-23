/* src/pl/plmysql/src/plmysql--1.0.sql */

CREATE FUNCTION plmysql_call_handler() RETURNS language_handler
  LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION plmysql_inline_handler(internal) RETURNS void
  STRICT LANGUAGE c AS 'MODULE_PATHNAME';

CREATE FUNCTION plmysql_validator(oid) RETURNS void
  STRICT LANGUAGE c AS 'MODULE_PATHNAME';

CREATE TRUSTED LANGUAGE plmysql
  HANDLER plmysql_call_handler
  INLINE plmysql_inline_handler
  VALIDATOR plmysql_validator;

ALTER LANGUAGE plmysql OWNER TO @extowner@;

COMMENT ON LANGUAGE plmysql IS 'PL/MySQL procedural language';

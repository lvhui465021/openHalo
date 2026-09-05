/* contrib/ngram/ngram--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION ngram" to load this file. \quit

-- Parser functions (PostgreSQL text-search parser interface, same shape as
-- the core 'default' parser's prsd_*: START receives the input text and its
-- byte length).
CREATE FUNCTION ngram_start(internal, int4)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT PARALLEL SAFE;

CREATE FUNCTION ngram_nexttoken(internal, internal, internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT PARALLEL SAFE;

CREATE FUNCTION ngram_end(internal)
RETURNS void
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT PARALLEL SAFE;

CREATE FUNCTION ngram_lextype(internal)
RETURNS internal
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT PARALLEL SAFE;

-- Token aliases (openGauss names): zh_words, en_word, numeric, alnum,
-- grapsymbol, multisymbol.
CREATE TEXT SEARCH PARSER ngram (
    START    = ngram_start,
    GETTOKEN = ngram_nexttoken,
    END      = ngram_end,
    LEXTYPES = ngram_lextype,
    HEADLINE = pg_catalog.prsd_headline
);

-- Default configuration, mirroring openGauss: every token type goes to the
-- 'simple' dictionary (ngram output is indexed verbatim; MySQL's ngram
-- parser applies no stemming or stop words either).
CREATE TEXT SEARCH CONFIGURATION ngram (PARSER = ngram);
ALTER TEXT SEARCH CONFIGURATION ngram ADD MAPPING
    FOR zh_words, en_word, numeric, alnum, grapsymbol, multisymbol
    WITH simple;

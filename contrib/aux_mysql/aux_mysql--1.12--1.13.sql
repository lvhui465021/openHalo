/* contrib/aux_mysql/aux_mysql--1.12--1.13.sql */

-- MySQL FULLTEXT MATCH(cols) AGAINST(query [mode]) support for the mys
-- dialect (mys_gram.y emits calls to mysql.match_against()).
--
-- The score-vs-predicate split: match_against() returns the float8
-- relevance score (0 when nothing matches), so SELECT lists and ORDER BY
-- get the MySQL-like numeric relevance, and WHERE/HAVING usage (the same
-- MySQL syntax) is served by match_against_bool(), into which the mys
-- analyzer rewrites match_against() calls in boolean position.
--
-- The underlying text search configuration comes from the custom GUC
-- mysql.ft_config (default 'simple').  Set it to 'ngram' (contrib/ngram)
-- for CJK text, mirroring MySQL's own WITH PARSER ngram choice.
--
-- Mode numbers (from mys_gram.y): 0 = natural language, 1 = boolean,
-- 2 = natural language with query expansion.
--
-- Implementation note: these bodies run in MySQL-protocol backends, where
-- plpgsql expression text is lexed by the MySQL scanner.  PostgreSQL-only
-- operators (@@, &&, ||, !!) are therefore avoided: tsquery text is
-- assembled with string concatenation and parsed in one to_tsquery() call;
-- matching uses ts_match_tsvector().
--
-- Known approximations vs MySQL 5.7:
--   * natural mode: all query words OR-ed (MySQL also drops words present
--     in >50% of rows as implicit stopwords; we do not);
--   * WITH QUERY EXPANSION degrades to natural mode;
--   * boolean mode: +word required, -word excluded, "phrase" exact
--     phrase, word* prefix supported; MySQL's optional bare words rank
--     only when required words exist (we ignore them for matching) and
--     other operators outside this subset degrade to plain OR terms.

CREATE OR REPLACE FUNCTION mysql.ft_parser_config()
RETURNS text
LANGUAGE sql STABLE
AS $$
    SELECT coalesce(NULLIF(current_setting('mysql.ft_config', true), ''), 'simple')
$$;

-- Natural language mode: query words OR-ed through the parser config.
CREATE OR REPLACE FUNCTION mysql.ft_natural_tsquery(q text)
RETURNS tsquery
LANGUAGE plpgsql STABLE
AS $fn$
DECLARE
    cfg text := mysql.ft_parser_config();
    tok text;
    parts text[] := '{}';
BEGIN
    FOR tok IN SELECT t FROM regexp_split_to_table(q, '[[:space:]]+') t WHERE t <> ''
    LOOP
        parts := parts || tok;
    END LOOP;
    IF cardinality(parts) = 0 THEN
        RETURN NULL;                /* nothing to search for */
    END IF;
    RETURN to_tsquery(cfg::regconfig, array_to_string(parts, ' | '));
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END
$fn$;

-- Boolean mode: MySQL boolean operators -> tsquery text, parsed once by
-- the parser config.  Tokens are split on whitespace with double-quoted
-- phrases kept intact.
CREATE OR REPLACE FUNCTION mysql.ft_bool_tsquery(q text)
RETURNS tsquery
LANGUAGE plpgsql STABLE
AS $fn$
DECLARE
    cfg text := mysql.ft_parser_config();
    i int;
    ch text;
    cur text := '';
    in_phrase boolean := false;
    tokens text[] := '{}';
    t text;
    pos text[] := '{}';          -- required ('&'-joined) terms
    neg text[] := '{}';          -- excluded terms
    opt text[] := '{}';          -- optional ('|'-joined) terms
    textq text := '';
BEGIN
    FOR i IN 1..length(q)
    LOOP
        ch := substr(q, i, 1);
        IF ch = '"' THEN
            IF in_phrase THEN
                /* closing quote: push the phrase, quoted marker kept */
                tokens := tokens || concat('"', cur, '"');
                cur := '';
                in_phrase := false;
            ELSE
                IF cur <> '' THEN
                    tokens := tokens || cur;
                    cur := '';
                END IF;
                in_phrase := true;
            END IF;
        ELSIF ch = ' ' OR ch = chr(9) OR ch = chr(10) THEN
            IF NOT in_phrase AND cur <> '' THEN
                tokens := tokens || cur;
                cur := '';
            ELSIF in_phrase THEN
                cur := concat(cur, ch);
            END IF;
        ELSE
            cur := concat(cur, ch);
        END IF;
    END LOOP;
    IF cur <> '' THEN
        tokens := tokens || cur;
    END IF;

    FOREACH t IN ARRAY tokens
    LOOP
        IF t = '' THEN
            CONTINUE;
        END IF;
        IF substr(t, 1, 1) = '"' AND substr(t, length(t), 1) = '"' THEN
            -- exact phrase: word <-> word ...
            pos := pos || concat('(', replace(regexp_replace(
                     substr(t, 2, length(t) - 2), '[[:space:]]+', ' ', 'g'), ' ', ' <-> '), ')');
        ELSIF substr(t, 1, 1) = '+' THEN
            pos := pos || substr(t, 2);
        ELSIF substr(t, 1, 1) = '-' THEN
            neg := neg || substr(t, 2);
        ELSIF substr(t, length(t), 1) = '*' THEN
            opt := opt || concat(substr(t, 1, length(t) - 1), ':*');
        ELSE
            opt := opt || t;
        END IF;
    END LOOP;

    IF cardinality(pos) > 0 THEN
        textq := concat('(', array_to_string(pos, ' & '), ')');
    ELSIF cardinality(opt) > 0 THEN
        textq := concat('(', array_to_string(opt, ' | '), ')');
    ELSE
        RETURN NULL;                /* only negative terms match nothing */
    END IF;
    IF cardinality(neg) > 0 THEN
        textq := concat(textq, ' & !', array_to_string(neg, ' & !'));
    END IF;
    RETURN to_tsquery(cfg::regconfig, textq);
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END
$fn$;

-- Relevance score (MySQL-style: non-matching rows score 0).
CREATE OR REPLACE FUNCTION mysql.match_against(doc text, q text, mode int)
RETURNS float8
LANGUAGE plpgsql STABLE
AS $fn$
DECLARE
    cfg text := mysql.ft_parser_config();
    tq tsquery;
    tsv tsvector;
BEGIN
    IF doc IS NULL OR q IS NULL OR q = '' THEN
        RETURN 0.0;
    END IF;
    IF mode = 1 THEN
        tq := mysql.ft_bool_tsquery(q);
    ELSE
        tq := mysql.ft_natural_tsquery(q);
        -- mode 2 (WITH QUERY EXPANSION) currently degrades to natural mode
    END IF;
    IF tq IS NULL THEN
        RETURN 0.0;
    END IF;
    tsv := to_tsvector(cfg::regconfig, doc);
    IF ts_match_vq(tsv, tq) THEN
        RETURN ts_rank(tsv, tq);
    END IF;
    RETURN 0.0;
END
$fn$;

-- Boolean variant used by the mys analyzer in WHERE/HAVING position.
CREATE OR REPLACE FUNCTION mysql.match_against_bool(doc text, q text, mode int)
RETURNS boolean
LANGUAGE plpgsql STABLE
AS $fn$
BEGIN
    RETURN mysql.match_against(doc, q, mode) > 0.0;
END
$fn$;

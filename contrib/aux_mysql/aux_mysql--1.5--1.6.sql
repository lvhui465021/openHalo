/*
 * aux_mysql 1.5 -> 1.6
 *
 * openHalo's MySQL stored procedure support lives in the separate "plmysql"
 * procedural language.  New installations get it automatically through this
 * extension's control file:
 *
 *     requires = 'plmysql'
 *         -> CREATE EXTENSION aux_mysql [CASCADE]
 *
 * But the "requires" line is only honored when the extension is installed --
 * a database that already has aux_mysql 1.5 keeps working without plmysql
 * after the server binaries are upgraded, and "CREATE PROCEDURE ... BEGIN
 * ... END" fails there with "language plmysql does not exist".
 *
 * This upgrade script cannot install plmysql itself: PostgreSQL does not
 * support nested CREATE EXTENSION (extension.c), so a scripted
 * "CREATE EXTENSION plmysql" from inside an extension update is not possible.
 * The documented upgrade procedure is, per database:
 *
 *     CREATE EXTENSION plmysql;
 *     ALTER EXTENSION aux_mysql UPDATE;
 *
 * The check below therefore only makes the second step fail loudly when the
 * first one was skipped, so an upgrade cannot silently report success while
 * MySQL stored routines remain unusable in the database.
 */
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_language WHERE lanname = 'plmysql') THEN
        RAISE EXCEPTION USING
            ERRCODE = 'feature_not_supported',
            MESSAGE = 'extension "aux_mysql" cannot be updated to 1.6: required language "plmysql" is not installed in this database',
            HINT = 'Run "CREATE EXTENSION plmysql;" in this database, then re-run "ALTER EXTENSION aux_mysql UPDATE;".';
    END IF;
END
$$;

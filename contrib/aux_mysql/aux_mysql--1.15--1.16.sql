/*
 * aux_mysql 1.15 -> 1.16
 *
 * Corpus environment parity: mysql-test-run's servers start with
 * --default-storage-engine=MyISAM, so the .result files expect
 * @@default_storage_engine = 'MyISAM' and ENGINE=MyISAM on implicitly
 * created tables.  Keep openHalo's registry default aligned with that
 * (engine choice is cosmetic here: relations do not map to engines).
 */
UPDATE mys_informa_schema.base_variables
   SET def_value = 'MyISAM',
       conf_value = 'MyISAM'
 WHERE variable_name = 'default_storage_engine';

/*
 * @@identity is a MySQL 5.7 synonym of LAST_INSERT_ID (variables.test
 * reads it next to last_insert_id()); register it so the name resolves
 * at top level and in the plmysql compile-time sysvar validation.  It
 * registers as a plain writable session variable -- the LAST_INSERT_ID
 * read semantics are not wired up.  ON CONFLICT because test_011's
 * rewind-to-1.5 simulation re-runs this migration over a database that
 * already applied it.
 */
INSERT INTO mys_informa_schema.base_variables
VALUES ('identity', '0', '0', 2, true, true, null, null, null)
ON CONFLICT (variable_name) DO NOTHING;

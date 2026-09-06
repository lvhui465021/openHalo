/*
 * aux_mysql 1.14 -> 1.15
 *
 * Give mys_informa_schema.triggers a deterministic row order: MySQL
 * returns a table's triggers in creation order, while the view used to
 * have no ORDER BY and exposed whatever scan order the planner picked
 * (information_schema.TRIGGERS row sets then flipped between runs as
 * catalog contents changed).  Creation order is pg_trigger.oid order.
 */

DROP VIEW IF EXISTS mys_informa_schema.triggers;
CREATE VIEW mys_informa_schema.triggers AS
SELECT 'def'::varchar AS trigger_catalog,
       n.nspname::varchar AS trigger_schema,
       t.tgname::varchar AS trigger_name,
       em.text::varchar AS event_manipulation,
       'def'::varchar AS event_object_catalog,
       n.nspname::varchar AS event_object_schema,
       c.relname::varchar AS event_object_table,
       rank() OVER (PARTITION BY (n.nspname::information_schema.sql_identifier),
                                   (c.relname::information_schema.sql_identifier),
                                   em.num, (t.tgtype::integer & 1),
                                   (t.tgtype::integer & 66)
                    ORDER BY t.tgname)::pg_catalog.int4 AS action_order,
       null::varchar AS action_condition,
       coalesce(mysql.get_plmysql_config(t.tgfoid, 'plmysql.trigger_body'),
                (SELECT prosrc FROM pg_proc WHERE oid = t.tgfoid))::text AS action_statement,
       CASE t.tgtype::integer & 1
           WHEN 1 THEN 'ROW'::text
           ELSE 'STATEMENT'::text
       END::varchar AS action_orientation,
       CASE t.tgtype::integer & 66
           WHEN 2 THEN 'BEFORE'::text
           WHEN 64 THEN 'INSTEAD OF'::text
           ELSE 'AFTER'::text
       END::varchar AS action_timing,
       null::varchar AS action_reference_old_table,
       null::varchar AS action_reference_new_table,
       'OLD'::varchar AS action_reference_old_row,
       'NEW'::varchar AS action_reference_new_row,
       coalesce(mysql.get_plmysql_config(t.tgfoid, 'plmysql.created'),
                '2024-1-1')::mysql.datetime AS created,
       coalesce(mysql.get_plmysql_config(t.tgfoid, 'plmysql.sql_mode'),
                'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION')::varchar AS sql_mode,
       coalesce(mysql.get_plmysql_config(t.tgfoid, 'plmysql.definer'),
                pg_catalog.concat(pg_get_userbyid(c.relowner), '@%'))::varchar AS definer,
       'utf8mb4'::varchar AS character_set_client,
       'utf8mb4_0900_ai_ci'::varchar AS collation_connection,
       'utf8mb4_0900_ai_ci'::varchar AS database_collation
FROM pg_namespace n,
     pg_class c,
     pg_trigger t,
     (VALUES (4, 'INSERT'::text), (8, 'DELETE'::text), (16, 'UPDATE'::text)) em(num, text)
WHERE n.oid = c.relnamespace
  AND c.oid = t.tgrelid
  AND (t.tgtype::integer & em.num) <> 0
  AND NOT t.tgisinternal
  AND NOT pg_is_other_temp_schema(n.oid)
  AND (pg_has_role(c.relowner, 'USAGE'::text)
       OR has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'::text)
       OR has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'::text))
ORDER BY t.oid, em.num;

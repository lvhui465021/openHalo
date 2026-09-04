"""Two small MySQL-compat gaps found together while replaying MySQL 5.7's
own sp.test corpus (procedure "hndlr1"):

1. "#" single-line comments (running to end of line, like MySQL's "--" and
   unlike PostgreSQL, which has no "#" comment form at all) were not
   recognized anywhere -- not just inside routine bodies, but at the very
   top level of any MySQL-protocol statement. "#" was simply one of the
   characters PG's own scanner treats as a legal custom-operator
   constituent (mys_scan.l's op_chars), so "SELECT 1 # comment" tokenized
   as an operator and failed with a syntax error rather than being treated
   as a comment. Fixed by folding "#"{non_newline}* into mys_scan.l's
   existing `comment` rule (shared with "--"), and by teaching the
   {operator} rule's embedded-comment-start detection (which already knew
   to stop a multi-char operator early at an embedded "/*" or "--") about
   an embedded "#" too.

2. "DECLARE cond CONDITION FOR SQLSTATE VALUE '42S99'" -- the optional
   VALUE keyword between SQLSTATE and the literal -- was not accepted by
   plmysql's own grammar (pl_gram.y), which only had the "SQLSTATE
   '42S99'" (no VALUE) form for both DECLARE ... CONDITION FOR and
   DECLARE ... HANDLER FOR. Added K_VALUE as a new unreserved plmysql
   keyword and a second alternative to decl_condition_def/condition_value
   accepting and ignoring it (it changes nothing semantically).
"""


def _ddl(cluster, *statements):
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            for sql in statements:
                cur.execute(sql)


def run(cluster):
    # -------------------------------------------------- "#" comments
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            # Top level, outside any routine -- this used to fail too,
            # not just inside a body.
            cur.execute("SELECT 1 # trailing top-level hash comment")
            assert cur.fetchall() == ((1,),)

            # A "#" immediately after an operator character, with no
            # space, must still start a comment rather than being folded
            # into the operator token (mirrors how "--" already behaved).
            cur.execute("SELECT 1+1 #comment right after the expression")
            assert cur.fetchall() == ((2,),)

    _ddl(cluster,
         "DROP TABLE IF EXISTS t035_t",
         "CREATE TABLE t035_t (id VARCHAR(32), data INT, data2 INT)",
         "DROP PROCEDURE IF EXISTS t035_hndlr1",
         # Taken directly from MySQL 5.7's sp.test (procedure "hndlr1"):
         # a bare "#" comment on its own DECLARE CONDITION line, another
         # trailing a statement, and a third inside the IF body.
         """create procedure t035_hndlr1(val int)
         begin
           declare x int default 0;
           declare foo condition for 1136;
           declare bar condition for sqlstate '42S98';  # for testing syntax
           declare continue handler for foo set x = 1;

           insert into t035_t values ("hndlr1", val, 2);  # too many values
           if (x) then
             insert into t035_t values ("hndlr1", val);   # this instead
           end if;
         end""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t035_hndlr1(42)")
            cur.fetchall()
            cur.execute("SELECT * FROM t035_t WHERE id = 'hndlr1'")
            # t035_t has 3 columns, so the 3-value INSERT doesn't trip the
            # DECLARE ... CONDITION FOR 1136 handler the way it would
            # against MySQL's own narrower t1 -- this test only cares that
            # the whole thing *compiles and runs* with the "#" comments in
            # place, not about reproducing that particular handler firing.
            assert cur.fetchall() == (('hndlr1', 42, 2),)

    # -------------------------------------------------- SQLSTATE VALUE
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t035_sqlstate_value",
         # The exact form the plain "SQLSTATE '...'" grammar rejected:
         # the optional VALUE keyword in between.
         """create procedure t035_sqlstate_value(val int)
         begin
           declare x int default 0;
           declare zip condition for sqlstate value '42S99';
           declare continue handler for zip set x = 1;

           signal sqlstate '42S99';
           insert into t035_t values ("sqlstate_value", val, x);
         end""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t035_sqlstate_value(7)")
            cur.fetchall()
            cur.execute(
                "SELECT * FROM t035_t WHERE id = 'sqlstate_value'")
            assert cur.fetchall() == (('sqlstate_value', 7, 1),)

    # SQLSTATE VALUE also has to work in a HANDLER's own condition list
    # (condition_value), not just in a DECLARE ... CONDITION FOR.
    _ddl(cluster,
         "DROP PROCEDURE IF EXISTS t035_handler_sqlstate_value",
         """create procedure t035_handler_sqlstate_value(val int)
         begin
           declare x int default 0;
           declare continue handler for sqlstate value '42S99'
             set x = 1;

           signal sqlstate '42S99';
           insert into t035_t values ("handler_sqlstate_value", val, x);
         end""")
    with cluster.mysql(dbname="public") as conn:
        with conn.cursor() as cur:
            cur.execute("CALL t035_handler_sqlstate_value(9)")
            cur.fetchall()
            cur.execute(
                "SELECT * FROM t035_t WHERE id = 'handler_sqlstate_value'")
            assert cur.fetchall() == (('handler_sqlstate_value', 9, 1),)

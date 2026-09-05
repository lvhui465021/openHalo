-- aux_mysql 1.11 -> 1.12
--
-- SQL SECURITY is now carried in the routine's plmysql label rather than
-- pg_proc.prosecdef (see the C2 fix); SHOW CREATE PROCEDURE/FUNCTION must
-- reflect the recorded characteristic instead of assuming DEFINER.
-- (Based on the 1.9--1.10 definitions, the latest previous revision.)

CREATE OR REPLACE FUNCTION mysql.get_proc_def(procName pg_catalog.text,
                                                procOwner pg_catalog.text,
                                                proargtypes pg_catalog.oidvector,
                                                proallargtypes pg_catalog.oid[],
                                                proargmodes "char"[],
                                                proargnames pg_catalog.text[],
                                                prosrc pg_catalog.text,
                                                procOid pg_catalog.oid)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    allArgNum pg_catalog.int4;
    argIndex pg_catalog.int4;
    argTypes pg_catalog.int4[];
    definerVal pg_catalog.text;
    definerUser pg_catalog.text;
    definerHost pg_catalog.text;
    dataAccessVal pg_catalog.text;
    atPos pg_catalog.int4;
BEGIN
    definerVal := coalesce(mysql.get_plmysql_config($8, 'plmysql.definer'),
                           pg_catalog.concat($2, '@%'));
    atPos := pg_catalog.strpos(definerVal, '@');
    if (atPos > 0) then
        definerUser := pg_catalog.substr(definerVal, 1, atPos - 1);
        definerHost := pg_catalog.substr(definerVal, atPos + 1);
    else
        definerUser := definerVal;
        definerHost := '%';
    end if;
    dataAccessVal := mysql.get_plmysql_sql_data_access($8);

    ret := 'CREATE DEFINER=`';
    ret := pg_catalog.concat(ret, definerUser);
    ret := pg_catalog.concat(ret, '`@`');
    ret := pg_catalog.concat(ret, definerHost);
    ret := pg_catalog.concat(ret, '` PROCEDURE `');
    ret := pg_catalog.concat(ret, procName);
    ret := pg_catalog.concat(ret, '`(');
    if (proallargtypes is not null) then
        allArgNum := array_length(proallargtypes, 1);
        argIndex := 1;
        LOOP
            if (1 < argIndex) then
                ret := pg_catalog.concat(ret, ', ');
            end if;

            if (proargmodes[argIndex] = 'i') then
                ret := pg_catalog.concat(ret, 'IN');
            elsif (proargmodes[argIndex] = 'b') then
                ret := pg_catalog.concat(ret, 'INOUT');
            else
                ret := pg_catalog.concat(ret, 'OUT');
            end if;

            ret := pg_catalog.concat(ret, ' ');
            ret := pg_catalog.concat(ret, proargnames[argIndex]);
            ret := pg_catalog.concat(ret, ' ');
            ret := pg_catalog.concat(ret, proallargtypes[argIndex]::regType::pg_catalog.text);

            argIndex := argIndex + 1;
            EXIT WHEN argIndex > allArgNum;
        END LOOP;
    else
        argTypes := string_to_array(proargtypes::text, ' ');
        allArgNum := array_length(argTypes, 1);
        if (0 < allArgNum) then
            argIndex := 1;
            LOOP
                if (1 < argIndex) then
                    ret := pg_catalog.concat(ret, ',');
                end if;

                ret := pg_catalog.concat(ret, ' IN');
                ret := pg_catalog.concat(ret, ' ');
                ret := pg_catalog.concat(ret, proargnames[argIndex]);
                ret := pg_catalog.concat(ret, ' ');
                ret := pg_catalog.concat(ret, argTypes[argIndex]::regType::pg_catalog.text);

                argIndex := argIndex + 1;
                EXIT WHEN argIndex > allArgNum;
            END LOOP;
        end if;
    end if;
    ret := pg_catalog.concat(ret, ') ', dataAccessVal, '\n');
    IF mysql.get_plmysql_config($8, 'plmysql.sql_security') = 'INVOKER' THEN
        ret := pg_catalog.concat(ret, 'SQL SECURITY INVOKER\n');
    END IF;

    ret := pg_catalog.concat(ret, prosrc);
    RETURN ret;
END
$$
STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.get_func_def(funcName pg_catalog.text,
                                              procOwner pg_catalog.text,
                                              prorettype pg_catalog.oid,
                                              proargtypes pg_catalog.oidvector,
                                              proargnames pg_catalog.text[],
                                              prosrc pg_catalog.text,
                                              procOid pg_catalog.oid)
RETURNS pg_catalog.text
AS
$$
DECLARE
    ret pg_catalog.text;
    argTypes pg_catalog.int4[];
    allArgNum pg_catalog.int4;
    argIndex pg_catalog.int4;
    definerVal pg_catalog.text;
    definerUser pg_catalog.text;
    definerHost pg_catalog.text;
    dataAccessVal pg_catalog.text;
    atPos pg_catalog.int4;
BEGIN
    definerVal := coalesce(mysql.get_plmysql_config($7, 'plmysql.definer'),
                           pg_catalog.concat($2, '@%'));
    atPos := pg_catalog.strpos(definerVal, '@');
    if (atPos > 0) then
        definerUser := pg_catalog.substr(definerVal, 1, atPos - 1);
        definerHost := pg_catalog.substr(definerVal, atPos + 1);
    else
        definerUser := definerVal;
        definerHost := '%';
    end if;
    dataAccessVal := mysql.get_plmysql_sql_data_access($7);

    ret := 'CREATE DEFINER=`';
    ret := pg_catalog.concat(ret, definerUser);
    ret := pg_catalog.concat(ret, '`@`');
    ret := pg_catalog.concat(ret, definerHost);
    ret := pg_catalog.concat(ret, '` FUNCTION `');
    ret := pg_catalog.concat(ret, funcName);
    ret := pg_catalog.concat(ret, '`(');
    argTypes := string_to_array(proargtypes::text, ' ');
    allArgNum := array_length(argTypes, 1);
    argIndex := 1;
    if (0 < allArgNum) then
        LOOP
            if (1 < argIndex) then
                ret := pg_catalog.concat(ret, ', ');
            end if;

            ret := pg_catalog.concat(ret, proargnames[argIndex]);
            ret := pg_catalog.concat(ret, ' ');
            ret := pg_catalog.concat(ret, argTypes[argIndex]::regType::text);

            argIndex := argIndex + 1;
            EXIT WHEN argIndex > allArgNum;
        END LOOP;
    end if;
    ret := pg_catalog.concat(ret, ') RETURNS ', prorettype::regType::text,
                             ' ', dataAccessVal, '\n');
    IF mysql.get_plmysql_config($7, 'plmysql.sql_security') = 'INVOKER' THEN
        ret := pg_catalog.concat(ret, 'SQL SECURITY INVOKER\n');
    END IF;

    ret := pg_catalog.concat(ret, prosrc);
    RETURN ret;
END
$$
STABLE LANGUAGE PLPGSQL;


-- mysql.if with a TEXT condition: MySQL coerces the condition to a number
-- with leading-prefix semantics ("2:3" -> 2, "x" -> 0, "" -> 0).  The 612
-- generated numeric overloads only accept tinyint/double conditions, so an
-- IF(@user_var, ...) whose variable holds a string failed to resolve.
CREATE OR REPLACE FUNCTION mysql.str_prefix_double(s pg_catalog.text)
RETURNS float8
AS
$$
DECLARE
    d float8;
    t pg_catalog.text := pg_catalog.btrim(s);
BEGIN
    BEGIN
        d := t::float8;
    EXCEPTION
        WHEN OTHERS THEN
            -- leading numeric prefix, MySQL style
            t := pg_catalog.regexp_replace(t, '^([-+]?[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?).*$', '\\1');
            IF t IN ('', '+', '-') THEN
                d := 0;
            ELSE
                BEGIN
                    d := t::float8;
                EXCEPTION
                    WHEN OTHERS THEN
                        d := 0;
                END;
            END IF;
    END;
    RETURN d;
END;
$$
STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION mysql.if(condition pg_catalog.text,
                                    value2 pg_catalog.text,
                                    value3 pg_catalog.text)
RETURNS pg_catalog.text
AS
$$
BEGIN
    IF mysql.str_prefix_double(condition) != 0 THEN
        RETURN value2;
    ELSE
        RETURN value3;
    END IF;
END;
$$
STABLE LANGUAGE PLPGSQL;

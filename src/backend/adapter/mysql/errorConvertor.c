/*-------------------------------------------------------------------------
 *
 * errorConvertor.c
 *	  MySQL adapter errorConvertor routines
 *
 * 
 * 版权所有 (c) 2019-2025, 易景科技保留所有权利。
 * Copyright (c) 2019-2025, Halo Tech Co.,Ltd. All rights reserved.
 * 
 * 易景科技是Halo Database、Halo Database Management System、羲和数据
 * 库、羲和数据库管理系统（后面简称 Halo ）、openHalo软件的发明人同时也为
 * 知识产权权利人。Halo 软件的知识产权，以及与本软件相关的所有信息内容（包括
 * 但不限于文字、图片、音频、视频、图表、界面设计、版面框架、有关数据或电子文
 * 档等）均受中华人民共和国法律法规和相应的国际条约保护，易景科技享有上述知识
 * 产权，但相关权利人依照法律规定应享有的权利除外。未免疑义，本条所指的“知识
 * 产权”是指任何及所有基于 Halo 软件产生的：（a）版权、商标、商号、域名、与
 * 商标和商号相关的商誉、设计和专利；与创新、技术诀窍、商业秘密、保密技术、非
 * 技术信息相关的权利；（b）人身权、掩模作品权、署名权和发表权；以及（c）在
 * 本协议生效之前已存在或此后出现在世界任何地方的其他工业产权、专有权、与“知
 * 识产权”相关的权利，以及上述权利的所有续期和延长，无论此类权利是否已在相
 * 关法域内的相关机构注册。
 *
 * This software and related documentation are provided under a license
 * agreement containing restrictions on use and disclosure and are 
 * protected by intellectual property laws. Except as expressly permitted
 * in your license agreement or allowed by law, you may not use, copy, 
 * reproduce, translate, broadcast, modify, license, transmit, distribute,
 * exhibit, perform, publish, or display any part, in any form, or by any
 * means. Reverse engineering, disassembly, or decompilation of this 
 * software, unless required by law for interoperability, is prohibited.
 * 
 * This software is developed for general use in a variety of
 * information management applications. It is not developed or intended
 * for use in any inherently dangerous applications, including applications
 * that may create a risk of personal injury. If you use this software or
 * in dangerous applications, then you shall be responsible to take all
 * appropriate fail-safe, backup, redundancy, and other measures to ensure
 * its safe use. Halo Corporation and its affiliates disclaim any 
 * liability for any damages caused by use of this software in dangerous
 * applications.
 * 
 *
 * IDENTIFICATION
 *	  src/backend/adapter/mysql/errorConvertor.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "utils/hsearch.h"
#include "utils/errcodes.h"
#include "adapter/mysql/errorConvertor.h"

/*
 * MySQL errno explicitly attached to the error currently on its way to the
 * client (SIGNAL ... SET MYSQL_ERRNO).  The backend never calls into the
 * plmysql extension, so plmysql hands the value over through
 * mysSetPendingMySQLErrno() before raising the error; sendErrPacket() takes
 * and clears it when the error packet goes out.  A catch path in plmysql
 * clears it when the error is handled instead.
 */
static int mysPendingMySQLErrno = 0;

void
mysSetPendingMySQLErrno(int errorCode)
{
	mysPendingMySQLErrno = errorCode;
}

int
mysTakePendingMySQLErrno(void)
{
	int			e = mysPendingMySQLErrno;

	mysPendingMySQLErrno = 0;
	return e;
}


typedef struct 
{
    int haloErrorCode;   /* hash key must be first */
    int mySQLErrorCode;
} HaloMySQLErrorCode;
static HTAB *haloMysqlErrorCodes = NULL;

static void initErrorCode(int haloErrorCode, int mySQLErrorCode);


static void 
initErrorCode(int haloErrorCode, int mySQLErrorCode)
{
    HaloMySQLErrorCode *ret = NULL;
    bool found = false;

    ret = (HaloMySQLErrorCode *)hash_search(haloMysqlErrorCodes, 
                                            &haloErrorCode, 
                                            HASH_ENTER, 
                                            &found);
    if (found)
    {
        /* do nothing; */
    }
    else
    {
        ret->mySQLErrorCode = mySQLErrorCode;
    }
}


void 
initErrorCodeHashTable(void)
{
	HASHCTL hashctl;
	hashctl.keysize = sizeof(int);
	hashctl.entrysize = sizeof(HaloMySQLErrorCode);
    haloMysqlErrorCodes = hash_create("Halo MySQL(914) Error Codes", 
                                      32768, 
                                      &hashctl, 
                                      HASH_ELEM | HASH_BLOBS);

    /*
     * 有个比较麻烦的问题，halo的错误码和mysql的错误码不是一一对应的。
     *
     * Keys are PostgreSQL SQLSTATEs (as produced by MAKE_SQLSTATE); the two
     * "42W01"/"42W07"/"22W02"/"W0001" states are openHalo's own.  The
     * original list contained five dead entries whose keys were MySQL
     * errnos (1064/1292/1364/1411/2600) and could never match a PG
     * SQLSTATE, plus two wrong mappings: 42601 (syntax error) was reported
     * as 1478 instead of 1064, and the invalid-text-representation state
     * was reported as 1064 instead of 1366.  The 23514 (check_violation)
     * entry was dropped: MySQL 5.7 has no CHECK constraints, so it can only
     * ever fall through to the generic mapping below.
     */
    initErrorCode(16801924, 1064);      /* 42601 syntax error -> ER_PARSE_ERROR */
    initErrorCode(16908420, 1146);      /* 42W01 (openHalo undefined table) */
    initErrorCode(33575106, 1048);      /* 23502 not-null -> ER_BAD_NULL_ERROR */
    initErrorCode(33685634, 1366);      /* 22W02 (openHalo invalid text repr) */
    initErrorCode(50331778, 1264);      /* 22003 out of range -> ER_WARN_DATA_OUT_OF_RANGE */
    initErrorCode(50352322, 1452);      /* 23503 FK violation -> ER_NO_REFERENCED_ROW_2 */
    initErrorCode(50360452, 1054);      /* 42703 undefined column -> ER_BAD_FIELD_ERROR */
    initErrorCode(83906754, 1062);      /* 23505 unique -> ER_DUP_ENTRY */
    initErrorCode(117571716, 1050);     /* 42W07 (openHalo duplicate table) */
    initErrorCode(16777248, 1264);      /* W0001 (openHalo warning) */
    initErrorCode(16777346, 1406);      /* 22001 string right truncation -> ER_DATA_TOO_LONG */

    /*
     * Common conditions raised by stored routines, keyed by the standard
     * ERRCODE_* names so the mapping stays readable.
     */
    initErrorCode(ERRCODE_UNIQUE_VIOLATION, 1062);
    initErrorCode(ERRCODE_NOT_NULL_VIOLATION, 1048);
    initErrorCode(ERRCODE_FOREIGN_KEY_VIOLATION, 1452);
    initErrorCode(ERRCODE_UNDEFINED_TABLE, 1146);
    initErrorCode(ERRCODE_UNDEFINED_COLUMN, 1054);
    initErrorCode(ERRCODE_SYNTAX_ERROR, 1064);
    initErrorCode(ERRCODE_DUPLICATE_TABLE, 1050);
    initErrorCode(ERRCODE_UNDEFINED_FUNCTION, 1305);
    initErrorCode(ERRCODE_INVALID_TEXT_REPRESENTATION, 1366);
    initErrorCode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION, 1406);
    initErrorCode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE, 1264);
    initErrorCode(ERRCODE_DIVISION_BY_ZERO, 1365);
    initErrorCode(ERRCODE_DATETIME_FIELD_OVERFLOW, 1292);
    initErrorCode(ERRCODE_INVALID_DATETIME_FORMAT, 1292);
    initErrorCode(ERRCODE_AMBIGUOUS_COLUMN, 1052);
    initErrorCode(ERRCODE_NAME_TOO_LONG, 1059);
    initErrorCode(ERRCODE_NO_DATA, 1329);
    initErrorCode(ERRCODE_T_R_DEADLOCK_DETECTED, 1213);
    initErrorCode(ERRCODE_LOCK_NOT_AVAILABLE, 1205);
    initErrorCode(ERRCODE_QUERY_CANCELED, 1317);

    /*
     * Broader DDL/DML/routine map (the spec's 40-60 entry target): errno
     * chosen per common scenario, MySQL 5.7 names in the comments.
     */
    initErrorCode(ERRCODE_DUPLICATE_DATABASE, 1007);            /* ER_DB_CREATE_EXISTS */
    initErrorCode(ERRCODE_UNDEFINED_DATABASE, 1049);            /* ER_BAD_DB_ERROR */
    initErrorCode(ERRCODE_UNDEFINED_SCHEMA, 1049);              /* ER_BAD_DB_ERROR */
    initErrorCode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION, 1045); /* ER_ACCESS_DENIED_ERROR */
    initErrorCode(ERRCODE_INSUFFICIENT_PRIVILEGE, 1142);        /* ER_TABLEACCESS_DENIED_ERROR */
    initErrorCode(ERRCODE_DUPLICATE_COLUMN, 1060);              /* ER_DUP_FIELDNAME */
    initErrorCode(ERRCODE_DUPLICATE_FUNCTION, 1304);            /* ER_SP_ALREADY_EXISTS */
    initErrorCode(ERRCODE_UNDEFINED_OBJECT, 1091);              /* ER_CANT_DROP_FIELD_OR_KEY */
    initErrorCode(ERRCODE_DATATYPE_MISMATCH, 1366);             /* ER_TRUNCATED_WRONG_VALUE_FOR_FIELD */
    initErrorCode(ERRCODE_INVALID_COLUMN_REFERENCE, 1054);      /* ER_BAD_FIELD_ERROR */
    initErrorCode(ERRCODE_DUPLICATE_ALIAS, 1066);               /* ER_NONUNIQ_TABLE */
    initErrorCode(ERRCODE_READ_ONLY_SQL_TRANSACTION, 1792);     /* ER_CANT_EXECUTE_IN_READ_ONLY_TRANSACTION */
    initErrorCode(ERRCODE_T_R_SERIALIZATION_FAILURE, 1213);     /* ER_LOCK_DEADLOCK */
    initErrorCode(ERRCODE_T_R_DEADLOCK_DETECTED, 1213);         /* ER_LOCK_DEADLOCK */
    initErrorCode(ERRCODE_FEATURE_NOT_SUPPORTED, 1235);         /* ER_NOT_SUPPORTED_YET */
    initErrorCode(ERRCODE_INVALID_CURSOR_STATE, 1325);          /* ER_SP_CURSOR_NOT_OPEN */
    initErrorCode(ERRCODE_DUPLICATE_CURSOR, 1324);              /* ER_SP_CURSOR_ALREADY_OPEN */
    initErrorCode(ERRCODE_CARDINALITY_VIOLATION, 1172);         /* ER_TOO_MANY_ROWS */
    initErrorCode(ERRCODE_PROGRAM_LIMIT_EXCEEDED, 1114);        /* ER_TOO_MANY_TABLES */
    initErrorCode(ERRCODE_CONNECTION_FAILURE, 2006);            /* ER_SERVER_GONE_ERROR */
    initErrorCode(ERRCODE_CANNOT_CONNECT_NOW, 1040);            /* ER_CON_COUNT_ERROR */
    initErrorCode(ERRCODE_TOO_MANY_CONNECTIONS, 1040);          /* ER_CON_COUNT_ERROR */
    //initErrorCode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION, 
    //              HALO_ERR_DATA_TOO_LONG);
    //initErrorCode(ERRCODE_INVALID_TEXT_REPRESENTATION, 
    //              HALO_ERR_TRUNCATED_WRONG_VALUE_FOR_FIELD);
    //initErrorCode(ERRCODE_NOT_NULL_VIOLATION, 
    //              HALO_ERR_BAD_NULL_ERROR);
    //initErrorCode(ERRCODE_FOREIGN_KEY_VIOLATION, 
    //              HALO_ERR_NO_REFERENCED_ROW_2);
    //initErrorCode(ERRCODE_UNIQUE_VIOLATION, 
    //              HALO_ERR_DUP_ENTRY);
    //initErrorCode(ERRCODE_SYNTAX_ERROR, 
    //              HALO_ERR_PARSE_ERROR);
    //initErrorCode(ERRCODE_NAME_TOO_LONG, 
    //              HALO_ERR_TOO_LONG_IDENT);
    //initErrorCode(ERRCODE_AMBIGUOUS_COLUMN, 
    //              HALO_ERR_NON_UNIQ_ERROR);
    //initErrorCode(ERRCODE_UNDEFINED_COLUMN, 
    //              HALO_ERR_BAD_FIELD_ERROR);
    //initErrorCode(ERRCODE_DUPLICATE_ALIAS, 
    //              HALO_ERR_NONUNIQ_TABLE);
    //initErrorCode(ERRCODE_UNDEFINED_FUNCTION, 
    //              HALO_ERR_SP_DOES_NOT_EXIST);
    //initErrorCode(ERRCODE_UNDEFINED_TABLE, 
    //              HALO_ERR_BAD_TABLE_ERROR);
    //initErrorCode(ERRCODE_DUPLICATE_TABLE, 
    //              HALO_ERR_TABLE_EXISTS_ERROR);
    //initErrorCode(ERRCODE_DATETIME_FIELD_OVERFLOW, 
    //              HALO_ERR_TRUNCATED_WRONG_VALUE);
    //initErrorCode(ERRCODE_UNDEFINED_OBJECT, 
    //              HALO_ERR_ACCESS_DENIED_ERROR);
}

int 
convertErrorCode(int haloErrorCode)
{
    HaloMySQLErrorCode *ret = NULL;
    bool found = false;
    int  pending;

    /*
     * SIGNAL ... SET MYSQL_ERRNO bypasses the table entirely: the user
     * picked the exact MySQL error number to report.
     */
    pending = mysTakePendingMySQLErrno();
    if (pending > 0)
        return pending;

    if (haloMysqlErrorCodes != NULL)
    {
        ret = (HaloMySQLErrorCode *)hash_search(haloMysqlErrorCodes, 
                                                &haloErrorCode, 
                                                HASH_FIND, 
                                                &found);
        if (found)
        {
            return ret->mySQLErrorCode;
        }
    }

    /*
     * Unmapped errors used to fall through as the raw PG code, which shows
     * up on MySQL clients as an illegal errno in the millions.  Report the
     * generic ER_UNKNOWN_ERROR instead.
     */
    return 1105;
}

/*
 * Canonical MySQL SQLSTATEs for the PostgreSQL SQLSTATEs that the forward
 * table above produces, keyed by the PostgreSQL code and filled in from the
 * MySQL 5.7 manual's server-error appendix.  Only pairs where the two
 * spellings differ appear; a SIGNAL-chosen custom state (45000, A0001, ...)
 * is never a key, so user-selected SQLSTATEs still round-trip verbatim.
 * This is the wire-side companion of plmysql's errno<->SQLSTATE map, kept
 * here because sendErrPacket lives in core and must not link the extension.
 */
static const struct
{
    const char *pgstate;        /* SQLSTATE PostgreSQL raises */
    const char *mystate;        /* MySQL's canonical SQLSTATE for it */
} mysql_pgstate_canonical_map[] =
{
    {"23502", "23000"},         /* 1048 ER_BAD_NULL_ERROR */
    {"23503", "23000"},         /* 1451/1452 FK violation */
    {"23505", "23000"},         /* 1022/1062/1169 duplicate entry */
    {"40P01", "40001"},         /* 1213 ER_LOCK_DEADLOCK */
    {"42P01", "42S02"},         /* 1051/1146 ER_BAD_TABLE_ERROR/NO_SUCH_TABLE */
    {"42P07", "42S01"},         /* 1050 ER_TABLE_EXISTS_ERROR */
    {"42601", "42000"},         /* 1064/1149 ER_PARSE_ERROR */
    {"42622", "42000"},         /* 1059 ER_TOO_LONG_IDENT */
    {"42701", "42S21"},         /* 1060 ER_DUP_FIELDNAME */
    {"42702", "23000"},         /* 1052 ER_FIELD_SPECIFIED_TWICE */
    {"42703", "42S22"},         /* 1054 ER_BAD_FIELD_ERROR */
    {"42710", "42000"},         /* 1359 ER_TRG_ALREADY_EXISTS */
    {"42883", "42000"},         /* 1305 ER_SP_DOES_NOT_EXIST */
    {"42501", "42000"},         /* 1044 ER_DBACCESS_DENIED_ERROR */
    {"55P03", "HY000"},         /* 1205 ER_LOCK_WAIT_TIMEOUT (generic) */
    {"57014", "70100"},         /* 1317 ER_QUERY_INTERRUPTED */
    {"P0001", "45000"},         /* 1644 ER_SIGNAL_EXCEPTION */
};

bool
mysCanonicalizeSqlState(const char *sqlstate, char *out)
{
    int i;

    if (sqlstate == NULL || strlen(sqlstate) != 5)
        return false;
    for (i = 0; i < lengthof(mysql_pgstate_canonical_map); i++)
    {
        if (strcmp(mysql_pgstate_canonical_map[i].pgstate, sqlstate) == 0)
        {
            strcpy(out, mysql_pgstate_canonical_map[i].mystate);
            return true;
        }
    }
    return false;
}


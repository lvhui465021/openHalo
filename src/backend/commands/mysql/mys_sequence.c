/*-------------------------------------------------------------------------
 *
 * mys_sequence.c
 *	  MySQL auto_increment sequence handling
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/commands/mysql/mys_sequence.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/htup_details.h"
#include "access/sequence.h"
#include "access/table.h"
#include "access/transam.h"
#include "access/xact.h"
#include "access/xlog.h"
#include "access/xloginsert.h"
#include "catalog/pg_sequence.h"
#include "commands/sequence.h"
#include "miscadmin.h"
#include "storage/bufmgr.h"
#include "storage/bufpage.h"
#include "storage/lmgr.h"
#include "utils/acl.h"
#include "utils/relcache.h"
#include "utils/syscache.h"

/*
 * SeqTableData forward declaration (defined internally in sequence.c).
 * We only access 'last', 'last_valid', and 'cached' fields.
 */
typedef struct SeqTableData
{
	int64		last;
	int64		cached;
	bool		last_valid;
	/* ... other fields we don't touch ... */
} SeqTableData;

typedef SeqTableData *SeqTable;

/*
 * Forward declarations for internal functions from sequence.c.
 */
extern void init_sequence(Oid relid, SeqTable *p_elm, Relation *p_rel);
extern Form_pg_sequence_data read_seq_tuple(Relation rel,
						Buffer *buf, HeapTuple seqdatatuple);
void
Datum mys_setval3_oid(Oid seqOid, int64 next, bool isCalled)
{
    SeqTable elm;
	Relation seqRel;
    Buffer buf;
    HeapTupleData seqTuple;
    Form_pg_sequence_data seq;

    /* open and lock sequence */
	init_sequence(seqOid, &elm, &seqRel);

    if (pg_class_aclcheck(seqOid, GetUserId(), ACL_SELECT | ACL_USAGE | ACL_UPDATE) != ACLCHECK_OK)
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("permission denied for sequence %s",
						RelationGetRelationName(seqRel))));

    seq = read_seq_tuple(seqRel, &buf, &seqTuple);

    if (seq->last_value < next)
    {
        HeapTuple pgstuple;
        Form_pg_sequence pgsform;
        int64 maxv;
		int64 minv;

        pgstuple = SearchSysCache1(SEQRELID, ObjectIdGetDatum(seqOid));
        if (!HeapTupleIsValid(pgstuple))
            elog(ERROR, "cache lookup failed for sequence %u", seqOid);
        pgsform = (Form_pg_sequence) GETSTRUCT(pgstuple);
        maxv = pgsform->seqmax;
        minv = pgsform->seqmin;
        ReleaseSysCache(pgstuple);

        /* read-only transactions may only modify temp sequences */
        if (!seqRel->rd_islocaltemp)
            PreventCommandIfReadOnly("mys_setval_oid()");

        /*
         * Forbid this during parallel operation because, to make it work, the
         * cooperating backends would need to share the backend-local cached
         * sequence information.  Currently, we don't support that.
         */
        PreventCommandIfParallelMode("mys_setval_oid()");

        if ((next < minv) || (next > maxv))
        {
            char bufv[100];
            char bufm[100];
            char bufx[100];

            snprintf(bufv, sizeof(bufv), INT64_FORMAT, next);
            snprintf(bufm, sizeof(bufm), INT64_FORMAT, minv);
            snprintf(bufx, sizeof(bufx), INT64_FORMAT, maxv);
            ereport(ERROR,
                    (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
                    errmsg("mys_setval_oid: value %s is out of bounds for sequence \"%s\" (%s..%s)",
                            bufv, RelationGetRelationName(seqRel),
                            bufm, bufx)));
        }

        /* Set the currval() state only if iscalled = true */
        if (isCalled)
        {
            elm->last = next;		/* last returned number */
            elm->last_valid = true;
        }

        /* In any case, forget any future cached numbers */
        elm->cached = elm->last;

        /* check the comment above nextval_internal()'s equivalent call. */
        if (RelationNeedsWAL(seqRel))
            GetTopTransactionId();

        /* ready to change the on-disk (or really, in-buffer) tuple */
        START_CRIT_SECTION();

        seq->last_value = next;		/* last fetched number */
        seq->is_called = isCalled;
        seq->log_cnt = 0;

        MarkBufferDirty(buf);

        /* XLOG stuff */
        if (RelationNeedsWAL(seqRel))
        {
            xl_seq_rec xlrec;
            XLogRecPtr recptr;
            Page page = BufferGetPage(buf);

            XLogBeginInsert();
            XLogRegisterBuffer(0, buf, REGBUF_WILL_INIT);

            xlrec.locator = seqRel->rd_locator;
            XLogRegisterData((char *) &xlrec, sizeof(xl_seq_rec));
            XLogRegisterData((char *) seqTuple.t_data, seqTuple.t_len);

            recptr = XLogInsert(RM_SEQ_ID, XLOG_SEQ_LOG);

            PageSetLSN(page, recptr);
        }

        END_CRIT_SECTION();
    }
    else
    {
        /* Nothing to do */
    }

    UnlockReleaseBuffer(buf);
	RelationClose(seqRel);
}

/* M3 stub: not yet migrated from UDB-TX */
Form_pg_sequence_data
read_seq_tuple(Relation rel, Buffer *buf, HeapTupleData *tuple)
{
    ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                    errmsg("read_seq_tuple not yet implemented")));
    return NULL;
}


/*-------------------------------------------------------------------------
 * mysm_compat.h
 *    Compatibility shims for mysm code ported from openHalo/UDB-TX.
 *
 * openHalo had custom headers (unvdb.h, adapter/mysql/adapter.h, 
 * utils/fmgrprotos.h, utils/int8.h).  PG18 provides equivalents via
 * standard headers already included by each .c file.
 *------------------------------------------------------------------------- */
#ifndef MYSM_COMPAT_H
#define MYSM_COMPAT_H

/* openHalo adapter globals → PG18 MysPacketState accessors */
/* (each .c file includes the headers it needs) */

#endif /* MYSM_COMPAT_H */

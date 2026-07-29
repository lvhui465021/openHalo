/*-------------------------------------------------------------------------
 * mysm_compat.h
 *    Compatibility shims for mysm code ported from openHalo/UDB-TX.
 *
 * openHalo's mysm was built against PG14 with custom headers (unvdb.h,
 * adapter/mysql/adapter.h).  PG18 provides equivalents via standard
 * headers or mysql_packet.h session state.
 *-------------------------------------------------------------------------
 */
#ifndef MYSM_COMPAT_H
#define MYSM_COMPAT_H

#include "postgres.h"
#include "fmgr.h"

/* openHalo adapter globals → PG18 MysPacketState accessors */
#include "adapter/mysql/mysql_packet.h"

#endif /* MYSM_COMPAT_H */

/*-------------------------------------------------------------------------
 *
 * mys_adtext.h
 *    MySQL ADT compatibility: ADT extension method declarations.
 *
 * Portions Copyright (c) 2026, HaloLab / UDB-TX Contributors
 *
 * src/include/utils/mysql/mys_adtext.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef MYS_ADTEXT_H
#define MYS_ADTEXT_H

#include "utils/adtextapi.h"

/*
 * ADT Extra for Oracle Compatible
 */
extern const ADTExtMethod *GetMysADTExt(void);


#endif							/* MYS_ADTEXT_H */


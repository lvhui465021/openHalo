/*-------------------------------------------------------------------------
 *
 * adtext.h
 *    Global ADT Extension instance and initialization.
 *
 * Portions Copyright (c) 2026, HaloLab / openHalo Contributors
 *
 * src/include/utils/adtext.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef ADTEXT_H
#define ADTEXT_H

#include "utils/adtextapi.h"

/* ADT Extension global instance (set by InitADTExt) */
extern const ADTExtMethod *adtext;

/* Initialize the global ADT Extension based on protocol / database mode */
extern void InitADTExt(void);

/* Return the standard (pass-through) ADT Extension */
extern const ADTExtMethod *GetStandardADTExt(void);

#endif							/* ADTEXT_H */

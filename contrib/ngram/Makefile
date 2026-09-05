# contrib/ngram/Makefile
#
# Chinese ngram full-text-search parser, ported from openGauss
# (src/common/backend/tsearch/ts_zh_ngram.cpp, Mulan PSL v2) as a
# self-contained PGXS-style extension.

EXTENSION = ngram
DATA = ngram--1.0.sql

MODULE_big = ngram
OBJS = ts_zh_ngram.o
PGFILEDESC = "ngram - Chinese ngram full text search parser"

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/ngram
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

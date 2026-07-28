# contrib/mysql_adapter/Makefile

EXTENSION = mysql_adapter
DATA = mysql_adapter--1.0.sql mysql_adapter--1.0--1.1.sql mysql_adapter--1.1--1.0.sql mysql_adapter--1.1.sql

REGRESS = versioning

TAP_TESTS = 1

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/mysql_adapter
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

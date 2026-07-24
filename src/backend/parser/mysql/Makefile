#-------------------------------------------------------------------------
#
# Makefile for MySQL Compatible Parser
#
# src/backend/parser/mysql/Makefile
#
#-------------------------------------------------------------------------

subdir = src/backend/parser/mysql
top_builddir = ../../../..
include $(top_builddir)/src/Makefile.global

override CPPFLAGS := -I. -I$(srcdir) $(CPPFLAGS)

OBJS = \
	mys_keywords.o \
	mys_gram.o \
	mys_scan.o \
	mys_parser.o

include $(top_srcdir)/src/backend/common.mk

# Generate keyword-list hash table
TOOLSDIR = $(top_srcdir)/src/tools
GEN_KEYWORDLIST = $(PERL) -I $(TOOLSDIR) $(TOOLSDIR)/gen_keywordlist.pl
GEN_KEYWORDLIST_DEPS = $(TOOLSDIR)/gen_keywordlist.pl $(TOOLSDIR)/PerfectHash.pm

mys_kwlist_d.h: $(top_srcdir)/src/include/parser/mysql/mys_kwlist.h $(GEN_KEYWORDLIST_DEPS)
	$(GEN_KEYWORDLIST) --extern --varname=MysScanKeywords $<

mys_gram.h: mys_gram.c
	touch $@

mys_gram.c: BISONFLAGS += -r solved -d -v --warnings=none
mys_gram.c: BISON_CHECK_CMD = $(PERL) $(top_srcdir)/src/backend/parser/mysql/check_myskeywords.pl $< $(top_srcdir)/src/include/parser/mysql/mys_kwlist.h

mys_scan.c: FLEXFLAGS = -CF -p -p
mys_scan.c: FLEX_NO_BACKUP=yes
mys_scan.c: FLEX_FIX_WARNING=yes

# Force these dependencies to be known even without dependency info built:
mys_keywords.o mys_gram.o mys_scan.o mys_parser.o: mys_gram.h mys_kwlist_d.h

clean distclean maintainer-clean:
	rm -f lex.backup mys_kwlist_d.h

# src/test/mysql/Makefile

# aux_mysql lives in contrib/ and is not part of the core "make install",
# so "make check"'s automatic temp-install (see temp-install/checkprep in
# src/Makefile.global) would otherwise stage a tree without it.
EXTRA_INSTALL = contrib/aux_mysql

subdir = src/test/mysql
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

# NOTE: plain "PYTHON ?= python3" does not work here: src/Makefile.global
# unconditionally defines PYTHON (empty, unless configured --with-python),
# and "?=" only applies to a variable that was never assigned at all, not
# one that is merely empty. Fall back explicitly when it is blank.
ifeq ($(PYTHON),)
PYTHON = python3
endif
TESTBASEDIR ?= $(CURDIR)/tmp_check

check:
	$(with_temp_install) $(PYTHON) $(srcdir)/run_tests.py '$(abs_top_builddir)/tmp_install$(bindir)' '$(TESTBASEDIR)'

clean distclean maintainer-clean:
	rm -rf $(TESTBASEDIR)

.PHONY: check

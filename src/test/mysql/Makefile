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

# Plain "$(bindir)" is wrong here: "check" implicitly depends on
# Makefile.global's temp-install, which stages a full reinstall under
# DESTDIR=.../tmp_install, so the real binaries end up nested at
# tmp_install<abs-configure-prefix>/bin, not tmp_install/bin, and are linked
# with rpaths for the final (non-nested) prefix. $(with_temp_install) sets
# PATH/LD_LIBRARY_PATH for that nested tree, and
# "$(abs_top_builddir)/tmp_install$(bindir)" is the matching bindir to pass
# run_tests.py; both are the same idiom Makefile.global itself defines
# with_temp_install for (see also src/interfaces/ecpg/test/Makefile).
check:
	$(with_temp_install) $(PYTHON) $(srcdir)/run_tests.py '$(abs_top_builddir)/tmp_install$(bindir)' '$(TESTBASEDIR)'

clean distclean maintainer-clean:
	rm -rf $(TESTBASEDIR)

.PHONY: check

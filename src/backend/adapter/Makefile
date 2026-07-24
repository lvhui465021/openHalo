#-------------------------------------------------------------------------
#
# Makefile--
#    Makefile for src/backend/adapter
#
# IDENTIFICATION
#    src/backend/adapter/Makefile
#
#-------------------------------------------------------------------------

subdir = src/backend/adapter
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global

OBJS = \
	adapter_stub.o \
	mysql/mysql_packet.o \
	mysql/mysql_auth.o \
	mysql/mysql_command.o \
	mysql/mysql_protocol.o

include $(top_srcdir)/src/backend/common.mk

# Process this file with autoconf to create configure.
AC_PREREQ([2.65])

# ====================
# Version informations
# ====================
m4_define([autoinst_version_major],[1])
m4_define([autoinst_version_minor],[1])
m4_define([autoinst_version_micro],[0])
m4_define([autoinst_version],[autoinst_version_major.autoinst_version_minor.autoinst_version_micro])

# =============
# Automake init
# =============
AC_INIT([os-autoinst],[autoinst_version],[https://gitorious.org/os-autoinst])
AC_CONFIG_MACRO_DIR([m4])
AM_INIT_AUTOMAKE([1.11 foreign dist-xz])
AM_SILENT_RULES([yes])

# ===============
# Basic app check
# ===============
AC_PROG_CXX
AC_PROG_LIBTOOL
AC_PROG_MKDIR_P
PKG_PROG_PKG_CONFIG([0.20])

AC_CHECK_PROG([PERL], [perl], [/usr/bin/perl], [
        AC_MSG_ERROR([Cannot find perl])
])
AC_MSG_CHECKING([perl CFLAGS])
PERL_CFLAGS=`perl -MExtUtils::Embed -e ccopts`
AC_MSG_RESULT([$PERL_CFLAGS])
AC_SUBST([PERL_CFLAGS])

PKG_CHECK_MODULES([OPENCV], [opencv >= 2.4])
PKG_CHECK_MODULES([THEORAENC], [theoraenc >= 1.1])

AC_CONFIG_FILES([
	Makefile
	t/Makefile
])
AC_OUTPUT

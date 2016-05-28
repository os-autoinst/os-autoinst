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
AC_INIT([os-autoinst],[autoinst_version],[https://github.com/os-autoinst/os-autoinst])
AC_CONFIG_MACRO_DIR([m4])
AM_INIT_AUTOMAKE([1.11 foreign dist-xz])
AM_SILENT_RULES([yes])

# ===============
# Basic app check
# ===============
AC_PROG_CXX
AX_CXX_COMPILE_STDCXX([11], [], [mandatory])
AC_PROG_LIBTOOL
AC_PROG_MKDIR_P
PKG_PROG_PKG_CONFIG([0.20])

AC_MSG_CHECKING([perl CFLAGS])
PERL_CFLAGS=`perl -MExtUtils::Embed -e ccopts`
AC_MSG_RESULT([$PERL_CFLAGS])
AC_SUBST([PERL_CFLAGS])

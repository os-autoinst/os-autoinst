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
PKG_PROG_PKG_CONFIG([0.20])

# =======================
# Check if we want opencv
# =======================
AC_ARG_WITH([opencv],
	[AS_HELP_STRING([--with-opencv], [Link against openCV, which is used for kvm2usb to deal with noise on analog signal.])],
	[with_opencv="$withval"],
	[with_opencv=no]
)
AS_IF([test "x$with_opencv" != "xno"], [
	# =====================================
	# Check for swig and related perl tools
	# =====================================
	AC_CHECK_PROG([SWIG], [swig], [/usr/bin/swig], [
		AC_MSG_ERROR([Cannot find swig])
	])
	AC_CHECK_PROG([PERL], [perl], [/usr/bin/perl], [
		AC_MSG_ERROR([Cannot find perl])
	])
	AC_MSG_CHECKING([perl CFLAGS])
	PERL_CFLAGS=`perl -MExtUtils::Embed -e ccopts`
	AC_MSG_RESULT([$PERL_CFLAGS])
	AC_SUBST([PERL_CFLAGS])

	# ================
	# Check for openCV
	# ================
	PKG_CHECK_MODULES([OPENCV], [opencv >= 2.4])
])
AM_CONDITIONAL([WITH_OPENCV], [test "x$with_opencv" != "xno"])

AC_CONFIG_FILES([
	Makefile
	bin/isotovideo
])
AC_OUTPUT

# ==============================================
# Display final informations about configuration
# ==============================================
AC_MSG_NOTICE([
==============================================================================
Build configuration:
	opencv:          ${with_opencv}
==============================================================================
])

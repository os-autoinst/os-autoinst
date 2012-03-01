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

# ===========================
# Find required base packages
# ===========================
PKG_PROG_PKG_CONFIG([0.24])

# ==================
# Check dependencies
# ==================
AC_CHECK_PROG([KVM],[qemu-kvm],[yes])
AS_IF([test "x$KVM" != "xyes"], [
	AC_MSG_ERROR([Please install qemu-kvm before installing.])
])
AC_CHECK_PROG([PERL],[perl],[yes])
AS_IF([test "x$PERL" != "xyes"], [
	AC_MSG_ERROR([Please install perl before installing.])
])
# TODO:
#  Add checks for Time::HiRes and Algorithm::Line::Bresenham

PKG_CHECK_MODULES([IMAGEMAGICK],[ImageMagick])

AC_CONFIG_FILES([
	Makefile
	bin/isotovideo
])
AC_OUTPUT

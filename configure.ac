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

AC_CONFIG_FILES([
	Makefile
	bin/isotovideo
])
AC_OUTPUT

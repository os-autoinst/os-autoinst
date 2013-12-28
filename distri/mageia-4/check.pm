#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my $results=\%::results;


	$ENV{DESKTOP}="gnome";
	$ENV{NOAUTOLOGIN}=1;
	autotest::runtestdir("$ENV{CASEDIR}/test.d", \&::checkfunc);
#	autotest::runtestdir("$ENV{CASEDIR}/consoletest.d", \&::checkfunc);
#	autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&::checkfunc);
#	autotest::runtestdir("$ENV{CASEDIR}/consoletest.d", \&::checkfunc);
#	autotest::runtestdir("$ENV{CASEDIR}/x11test.d", \&::checkfunc);

#	my $overall=(::is_ok($results->{xterm}) or ::is_ok($results->{firefox}));
	my $overall=::is_ok($results->{consoletest_setup});
	return $overall;
}

1;

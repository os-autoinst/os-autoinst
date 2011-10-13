#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my $results=\%::results;
#	autotest::runtest("$scriptdir/distri/$ENV{DISTRI}/inst.d/010_initenv.pm",sub{my $test=shift;$test->run;});

	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/consoletest.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/x11test.d", \&::checkfunc);

	my $overall=(::is_ok($results->{xterm}) or ::is_ok($results->{firefox}) or ::is_ok($results->{yast2_users}));
	return $overall;
}

1;

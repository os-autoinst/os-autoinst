#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my $results=\%::results;
#	autotest::runtest("$scriptdir/distri/$ENV{DISTRI}/inst.d/010_initenv.pm",sub{my $test=shift;$test->run;});

	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/test.d", \&::checkfunc);

	my $overall=(::is_ok($results->{xterm}) || ::is_ok($results->{firefox}));
	return $overall;
}

1;

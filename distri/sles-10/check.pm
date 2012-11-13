#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my $results=\%::results;
#	autotest::runtest("$ENV{CASEDIR}/inst.d/010_initenv.pm",sub{my $test=shift;$test->run;});

	autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&::checkfunc);
	autotest::runtestdir("$ENV{CASEDIR}/test.d", \&::checkfunc);

	my $overall=(::is_ok($results->{xterm}) || ::is_ok($results->{firefox}));
	return $overall;
}

1;

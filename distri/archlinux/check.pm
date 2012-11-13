#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my $results=\%::results;

	autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&::checkfunc);
	autotest::runtestdir("$ENV{CASEDIR}/consoletest.d", \&::checkfunc);

	my $overall=(::is_ok($results->{pacman}), and ::is_ok($results->{reboot}));
	return $overall;
}

1;

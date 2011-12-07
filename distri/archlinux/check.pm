#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my $results=\%::results;

	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/consoletest.d", \&::checkfunc);

	my $overall=(::is_ok($results->{pacman}), and ::is_ok($results->{reboot}));
	return $overall;
}

1;

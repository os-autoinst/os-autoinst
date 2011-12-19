#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	my $results=\%::results;

	$ENV{DESKTOP}="gnome";
	$ENV{NOAUTOLOGIN}=1;
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&::checkfunc);
#	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/consoletest.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/x11test.d", \&::checkfunc);

	my $overall=(::is_ok($results->{xterm}) or ::is_ok($results->{firefox}));
	return $overall;
}

1;

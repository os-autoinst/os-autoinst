#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	$ENV{NOAUTOLOGIN}=1;
	$ENV{DESKTOP}||="gnome";
	my $results=\%::results;
#	autotest::runtest("$scriptdir/distri/$ENV{DISTRI}/inst.d/010_initenv.pm",sub{my $test=shift;$test->run;});

	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/consoletest.d", \&::checkfunc);
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/x11test.d", \&::checkfunc);

	my $overall=::is_ok($results->{curl_ipv6}) && (::is_ok($results->{xterm}) || ::is_ok($results->{firefox}) || ::is_ok($results->{yast2_users}));
	return $overall;
}

1;

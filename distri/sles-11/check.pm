#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;
use autotest;

sub check() {
	$ENV{NOAUTOLOGIN}=1;
	$ENV{DESKTOP}||="gnome";
	my $results=\%::results;
#	autotest::runtest("$ENV{CASEDIR}/inst.d/010_initenv.pm",sub{my $test=shift;$test->run;});

	autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&::checkfunc);
	autotest::runtestdir("$ENV{CASEDIR}/consoletest.d", \&::checkfunc);
	autotest::runtestdir("$ENV{CASEDIR}/x11test.d", \&::checkfunc);

	my $overall=::is_ok($results->{sshd}) && (::is_ok($results->{xterm}) || ::is_ok($results->{firefox}) || ::is_ok($results->{yast2_users}));
	return $overall;
}

1;

#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;

sub installrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	diag "starting $class";
	$test->run();
#	sleep 1; $test->take_screenshot;
	diag "finished $class";
}

if(!$ENV{LIVE} || !$ENV{LIVETEST}) {
	autotest::runtestdir("$scriptdir/suseinst.d", \&installrunfunc);
}

1;

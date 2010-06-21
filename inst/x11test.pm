#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;

sub x11testrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	diag "starting $class";
	$test->run();
	sleep 1; $test->take_screenshot;
	diag "finished $class";
}

autotest::runtestdir("$scriptdir/x11test.d", \&x11testrunfunc);

1;

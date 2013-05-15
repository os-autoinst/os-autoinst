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
	sleep 1; 
	$test->check_screen;
	diag "finished $class";
}

autotest::runtestdir("$ENV{CASEDIR}/x11test.d", \&x11testrunfunc);

1;

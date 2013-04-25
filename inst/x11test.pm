#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;

sub x11testrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	diag "starting $class";
	bmwqemu::set_current_test($test);
	$test->run();
	bmwqemu::set_current_test(undef);
	sleep 1; 
	$test->take_screenshot;
	diag "finished $class";
}

autotest::runtestdir("$scriptdir/x11test.d", \&x11testrunfunc);

1;

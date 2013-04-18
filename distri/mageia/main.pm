#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;

sub installrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	$test->run();
	$test->take_screenshot;
}
my $testcount=0;
sub consoletestrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	if($testcount++) {
		clear_console; # clear screen to make screen content independent from previous tests
	}
	$test->run();
	sleep 2;
	$test->take_screenshot;
}


autotest::runtestdir("$ENV{CASEDIR}/inst.d", undef);
autotest::runtestdir("$ENV{CASEDIR}/consoletest.d", undef);

if ($ENV{AUTO_INST}) {
	autotest::runtestdir("$ENV{CASEDIR}/auto_inst.d", \&installrunfunc);
}
elsif(!$ENV{LIVECD} || !$ENV{LIVETEST}) {
	autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&installrunfunc);
#	autotest::runtestdir("$ENV{CASEDIR}/test.d", \&installrunfunc);
} else {
}

set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	);

autotest::runtestdir("$ENV{CASEDIR}/consoletest.d", \&consoletestrunfunc);


1;

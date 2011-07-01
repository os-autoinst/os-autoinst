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
	$test->take_screenshot;
	diag "finished $class";
}
sub consoletestrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	clear_console; # clear screen to make screen content independent from previous tests
	diag "starting $class";
	$test->run();
	sleep 2;
	$test->take_screenshot;
	diag "finished $class";
}

$ENV{DESKTOP}||="gnome";

if(!$ENV{LIVECD} || !$ENV{LIVETEST}) {
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&installrunfunc);
} else {
}

set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	);

sendkey "ctrl-alt-f3"; waitidle; # avoid "reset" being typed into tty2 or 7
autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/consoletest.d", \&consoletestrunfunc);
autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/x11test.d", \&installrunfunc);

1;

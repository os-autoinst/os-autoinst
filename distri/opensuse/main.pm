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

waitinststage "bootloader",12; # wait for welcome animation to finish

if(!$ENV{LIVECD} || !$ENV{LIVETEST}) {
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&installrunfunc);
} else {
	$username="linux"; # LiveCD account
	$password="";
	autotest::runtest("$scriptdir/distri/$ENV{DISTRI}/inst.d/020_bootloader.pm", \&installrunfunc)
}

set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	);


1;

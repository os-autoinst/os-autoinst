#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;

sub installrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	$test->run();
#	sleep 1; $test->take_screenshot;
}

waitinststage "bootloader",12; # wait for welcome animation to finish

unless($ENV{LIVETEST} && ($ENV{LIVECD} || $ENV{PROMO})) {
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&installrunfunc);
} else {
	$username="linux"; # LiveCD account
	$password="";
	autotest::runtest("$scriptdir/distri/$ENV{DISTRI}/inst.d/020_bootloader.pm", \&installrunfunc)
}

set_std_hash_rects;

1;

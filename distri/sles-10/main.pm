#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;

# use NICMODEL=e1000

sub installrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	$test->run();
	$test->take_screenshot;
}

if(!$ENV{LIVECD} || !$ENV{LIVETEST}) {
	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/inst.d", \&installrunfunc);
} else {
}

set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	);

	autotest::runtestdir("$scriptdir/distri/$ENV{DISTRI}/test.d", \&installrunfunc);

1;

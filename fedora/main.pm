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

if(!$ENV{LIVECD} || !$ENV{LIVETEST}) {
	autotest::runtestdir("$scriptdir/fedora/inst.d", \&installrunfunc);
} else {
}

set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	);


1;

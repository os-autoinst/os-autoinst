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

$ENV{DESKTOP}="gnome";
$ENV{NOAUTOLOGIN}=1;
autotest::runtestdir("$ENV{CASEDIR}/inst.d", undef);
autotest::runtestdir("$ENV{CASEDIR}/x11test.d", undef);
if(!$ENV{LIVECD} || !$ENV{LIVETEST}) {
	autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&installrunfunc);
} else {
}

autotest::runtestdir("$ENV{CASEDIR}/x11test.d", \&installrunfunc);

set_hash_rects(
	[30,30,100,100], # where most applications pop up
	[630,30,100,100], # where some applications pop up
	[0,579,100,10 ], # bottom line (KDE/GNOME bar)
	);


1;

#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;
use needle;

sub installrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	$test->run();
	$test->take_screenshot;
}

sub remove_desktop_needles($)
{
	my $desktop = shift;
	if (!checkEnv("DESKTOP", $desktop)) {
		my @a = @{needle::tags("ENV-DESKTOP-$desktop")};
		for my $n (@a) {
			$n->unregister();
		}
	}
}
	
# wait for qemu to start
while (!getcurrentscreenshot()) {
	sleep 1;
}

remove_desktop_needles("lxde");
remove_desktop_needles("kde");
remove_desktop_needles("gnome");
remove_desktop_needles("xfce");
remove_desktop_needles("minimalx");
remove_desktop_needles("textmode");

#waitforneedle "inst-bootmenu",12; # wait for welcome animation to finish

if($ENV{LIVETEST} && ($ENV{LIVECD} || $ENV{PROMO})) {
	$username="linux"; # LiveCD account
	$password="";
}

if(checkEnv('DESKTOP', "minimalx")) {$ENV{XDMUSED}=1}
$ENV{TOGGLEHOME}=1;
autotest::runtestdir("$ENV{CASEDIR}/inst.d", undef);
autotest::runtestdir("$ENV{CASEDIR}/inst.d", \&installrunfunc);

if(my $d=$ENV{DESKTOP}) {
	require "inst/\L$d.pm";
}

1;

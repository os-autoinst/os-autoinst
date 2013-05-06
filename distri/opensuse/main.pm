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
}

# wait for qemu to start
while (!getcurrentscreenshot()) {
	sleep 1;
}

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

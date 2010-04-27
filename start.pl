#!/usr/bin/perl -w
use strict;
use bmwqemu;

my $init=1;

# init part
if($init) {
	if(!qemualive) {
		do "inst/startqemu.pm" or die @$;
	}
}
open_management_console;
do "inst/screenshot.pm" or die @$;
if($init) {
	waitgoodimage 9; # wait for welcome animation to finish
}

do "inst/bootloader.pm" or die @$;
sleep 11; # time to load kernel+initrd
do "inst/viewbootmsg.pm" or die @$;
sleep 40; # minimum time needed to boot up (includes some idles)
waitgoodimage 450;
do "inst/yast1.pm" or die @$;
#do "inst/partitioning.pm" or die @$;
do "inst/yast2.pm" or die @$;


for(1..6000) { # time to let install work
	sleep 1;
}


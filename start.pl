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
	sleep 9; # wait for welcome animation to finish
}

do "inst/bootloader.pm" or die @$;
sleep 11; # time to load kernel+initrd
do "inst/viewbootmsg.pm" or die @$;
sleep 40; # minimum time needed to boot up (includes some idles)
waitidle 40;
do "inst/yast1.pm" or die @$;
#do "inst/partitioning.pm" or die @$;
do "inst/yast2.pm" or die @$;


for(1..3000) { # time to let install work
	sleep 1;
}


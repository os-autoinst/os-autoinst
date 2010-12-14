#!/usr/bin/perl -w
use strict;
use bmwqemu;

my $init=1;
alarm (7200+($ENV{UPGRADE}?3600:0)); # worst case timeout

# init part
if($init) {
	if(!qemualive) {
		do "inst/startqemu.pm" or die $@;
	}
}
open_management_console;
qemusend_nolog(fileContent("$ENV{HOME}/.autotestvncpw")||"");
do "inst/screenshot.pm" or die $@;
if($init) {
	waitinststage "grub"; # wait for welcome animation to finish
}

do "inst/suseinst.pm" or die $@;

if(my $d=$ENV{DESKTOP}) {
	do "inst/\L$d.pm" or diag $@;
}


for(1..6000) { # time to let install work
	sleep 1;
}


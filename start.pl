#!/usr/bin/perl -w
use strict;
use bmwqemu;

my $init=1;
alarm (7200+($ENV{UPGRADE}?3600:0)); # worst case timeout

# init part
init_backend("qemu");
if($init) {
	if(!qemualive) {
		startvm or die $@;
	}
}
open_management_console;
my $size=-s $ENV{ISO}; diag("iso_size=$size");
qemusend_nolog(fileContent("$ENV{HOME}/.autotestvncpw")||"");
do "inst/screenshot.pm" or die $@;

if(!$ENV{DISTRI}) { die "DISTRI environment variable not set. unknown OS?" }
do "$scriptdir/distri/$ENV{DISTRI}/main.pm" or die $@;


for(1..6000) { # time to let install work
	sleep 1;
}


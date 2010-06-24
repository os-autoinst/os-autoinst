#!/usr/bin/perl -w
use strict;
use bmwqemu;

# wait until ready
waitinststage "GNOME", 1000;
waitidle 100;
sleep 10;

my $lastmenu=0;
# open application
sub open_application($;$)
{ my $name=shift; my $wait=shift;
	# alt-f2 for exec command
	sendkey "alt-f2";
	waitidle;
	sendautotype($name);
	sendkey "ret";
	waitidle $wait;
	sleep 3;
}

open_application("killall gnome-screensaver");
open_application("killall xscreensaver");

do "inst/consoletest.pm" or die @$;

#open_application("xterm");
#sendautotype ",.:;-_#'+*~`\\\"' \n"; # some chars can not be produced with sendkey in qemu-0.10

1;

#!/usr/bin/perl -w
use strict;
use bmwqemu;

# wait until ready
waitinststage "GNOME", 200;
mouse_hide(1);
waitidle 100;
sleep 10;

if(!$ENV{NICEVIDEO}) {
	x11_start_program("killall gnome-screensaver");
}

do "inst/consoletest.pm" or die @$;

#sendautotype ",.:;-_#'+*~`\\\"' \n"; # some chars can not be produced with sendkey in qemu-0.10

1;

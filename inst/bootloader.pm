#!/usr/bin/perl -w
use strict;
use bmwqemu;

# assume bios+grub+anim already waited in start.sh
# 1024x768
if(1||$ENV{LIVECD}) {
	# installation (instead of live):
	sendkey "down";
}
if($ENV{RES1024}) { # default is 800x600
	sendkey "f3";
	sendkey "down";
	sendkey "ret";
}
# German/Deutsch
if($ENV{INSTLANG} eq "de") {
	sendkey "f2";
	for(1..3) {
		sendkey "up";
	}
	sendkey "ret";
}
# boot
sendkey "ret";

1;

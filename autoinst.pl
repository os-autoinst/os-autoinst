#!/usr/bin/perl -w
use strict;
use bmwqemu;

# assume bios+grub+anim already waited in start.sh
sleep 1;
# 1024x768
sendkey "f3";
sendkey "down";
sendkey "ret";
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

sleep 80;

exec("./autoinst-yast.pl");

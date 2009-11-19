#!/usr/bin/perl -w
use strict;
use bmwqemu;

# bios+grub+anim
sleep 8;
# 1024x768
sendkey "f3";
sendkey "down";
sendkey "ret";
# German/Deutsch
sendkey "f2";
for(1..3) {
	sendkey "up";
}
sendkey "ret";
# boot
sendkey "ret";

sleep 60;

exec("./autoinst-yast.pl");

#!/usr/bin/perl -w
use strict;
use bmwqemu;

# assume bios+grub+anim already waited in start.sh
sleep 1;
# 1024x768
#sendkey "f3";
#sendkey "down";
#sendkey "ret";
# German/Deutsch
if($ENV{INSTLANG} eq "de") {
	sendkey "f2";
	for(1..3) {
		sendkey "up";
	}
	sendkey "ret";
}

# HTTP-source
{
	sendkey "f4";
	sendkey "ret";
	for(1..22) {
		sendkey "backspace"
	}
	sendautotype("ftp5.gwdg.de");
	sendkey "tab";
	# change dir
	# leave /repo/oss/
	for(1..10) { sendkey "left"; }
	for(1..22) { sendkey "backspace"; }
	sendautotype("/pub/opensuse/factory");
	sendkey "ret";
}

# HTTP-proxy
{
	sendkey "f4";
	for(1..4) {
		sendkey "down";
	}
	sendkey "ret";
	sendautotype("192.168.11.92\t3128\n");
}

# boot
sendkey "ret";

#sleep 80;

#exec("./autoinst-yast.pl");

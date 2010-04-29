#!/usr/bin/perl -w
use strict;
use bmwqemu;
use Time::HiRes qw(sleep);

# assume bios+grub+anim already waited in start.sh
# 1024x768
if(1||$ENV{LIVECD}) {
	# installation (instead of HDDboot on non-live)
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

# set HTTP-source to not use factory-snapshot
if($ENV{NETBOOT}) {
	sendkey "f4";
	sendkey "ret";
        #download.opensuse.org
        if($ENV{GWDG}) {
                for(1..22) { sendkey "backspace" }
                sendautotype("ftp5.gwdg.de");
        }
	sendkey "tab";
	# change dir
	# leave /repo/oss/ (10 chars)
	for(1..10) { sendkey "left"; }
	for(1..22) { sendkey "backspace"; }

        if($ENV{GWDG}) {
                sendautotype("/pub/opensuse/factory");
        } else {
                sendautotype("/factory");
        }

        sleep(1.5);
	sendkey "ret";
}

# HTTP-proxy
if($ENV{NETBOOT} && $ENV{HTTPPROXY} && $ENV{HTTPPROXY}=~m/([0-9.]+):(\d+)/) {
	my($proxyhost,$proxyport)=($1,$2);
	sendkey "f4";
	for(1..4) {
		sendkey "down";
	}
	sendkey "ret";
	sendautotype("$proxyhost\t$proxyport\n");
        sleep(1.5);
}

# add boot parameters
# ZYPP... enables proxy caching
sendautotype("ZYPP_ARIA2C=0"); sleep 2;

# boot
sendkey "ret";

1;

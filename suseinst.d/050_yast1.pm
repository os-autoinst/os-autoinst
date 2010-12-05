#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;

sub run()
{
waitinststage("welcome", 490);

if($ENV{BETA} && !$ENV{LIVECD}) {
	# ack beta message
	sendkey "ret";
	#sendkey $cmd{acceptlicense};
}

# animated cursor wastes disk space, so it is moved to bottom right corner
mousemove_raw(0x7fff,0x7fff); 
mousemove_raw(0x7fff,0x7fff); # work around no reaction first time
# license+lang
sendkey $cmd{"next"};
if(!$ENV{LIVECD}) {
	# autoconf phase
	waitinststage "systemanalysis";
	# includes downloads, so waitidle is bad.
	waitgoodimage(($ENV{UPGRADE}?120:25));
	# TODO waitstillimage(10)
	waitidle 29;
	# Installation Mode = new Installation
	if($ENV{UPGRADE}) {
		sendkey "alt-u";
	}
	sendkey $cmd{"next"};
}
if($ENV{UPGRADE}) {
	# upgrade system select
	waitidle;
	sendkey "alt-c"; # "Cancel" on warning popup (11.1->11.3)
	waitidle;
	sendkey "alt-s"; # "Show All Partitions"
	waitidle;

	sendkey $cmd{"next"};
	# repos
	waitidle;
	sendkey $cmd{"next"};
	waitidle;
	# might need to resolve conflicts here
	if($ENV{UPGRADE}=~m/11\.1/) {
		sendkey "alt-c";
		waitidle;
		sendkey "p";
		waitidle;
	# alt-c p # Change Packages
		for(1..4) {sendkey "tab"}
		sendkey "spc";
		sleep 3;
		sendkey "alt-o";
	# tab tab tab tab space alt-o # Select+OK
		waitidle;
		sendkey "alt-a";
		waitidle;
		sendkey "alt-o";
	# alt-a alt-o # Accept + Continue(with auto-changes)
	}
	sleep 120;
	sendkey "alt-u"; # Update if available
	waitidle 10;
	sendkey "alt-u"; # confirm
	sleep 20;
	sendkey "alt-d"; # details
	local $ENV{SCREENSHOTINTERVAL}=$ENV{SCREENSHOTINTERVAL}*10;
	sleep 3600; # time for install
	# TODO: use waitstillimage
	waitidle 4000;
}
}

1;

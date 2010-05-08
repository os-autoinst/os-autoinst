#!/usr/bin/perl -w
use strict;
use bmwqemu;

waitinststage("welcome", 490);

if($ENV{BETA} && !$ENV{LIVECD}) {
	# ack beta message
	sendkey "ret";
	#sendkey $cmd{acceptlicense};
}

# animated cursor wastes disk space, so it is moved to bottom right corner
qemusend "mouse_move 1000 1000"; 
sleep 1;
# license+lang
sendkey $cmd{"next"};
if(!$ENV{LIVECD}) {
	# autoconf phase
	# includes downloads, so waitidle is bad.
	sleep 29;
	waitidle 29;
	# new inst
	sendkey $cmd{"next"};
}
# timezone
waitinststage("timezone");
sendkey $cmd{"next"};
if(!$ENV{LIVECD}) {
	# KDE
	waitinststage "desktopselection";
	sendkey $cmd{"next"};
}
# ending at partition layout screen

1;

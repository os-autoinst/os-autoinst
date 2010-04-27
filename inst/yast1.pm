#!/usr/bin/perl -w
use strict;
use bmwqemu;

if($ENV{BETA}) {
	# ack beta message
	sendkey "ret";
	#sendkey $cmd{acceptlicense};
}

# animated cursor wastes disk space, so it is moved to bottom right corner
qemusend "mouse_move 1000 1000"; 
# license+lang
sendkey $cmd{"next"};
# autoconf phase
# includes downloads, so waitidle is bad.
sleep 15;
waitidle 15;
# new inst
sendkey $cmd{"next"};
# timezone
waitidle;
sendkey $cmd{"next"};
# KDE
waitidle;
sendkey $cmd{"next"};
waitidle;
# ending at partition layout screen

1;

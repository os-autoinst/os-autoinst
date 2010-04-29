#!/usr/bin/perl -w
use strict;
use bmwqemu;


if(!$ENV{NETBOOT}) {
	# LiveCD needs confirmation for reboot
	waitgoodimage(360);
	waitidle(99);
	sendkey $cmd{"rebootnow"};
	# eject CD
	for(1..100) {
		sleep 1;
		qemusend "eject ide1-cd0"; # will fail while locked
	}
	
	sleep 3;
	# hard reset
	qemusend "system_reset";
}

1;

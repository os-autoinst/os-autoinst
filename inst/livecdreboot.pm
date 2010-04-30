#!/usr/bin/perl -w
use strict;
use bmwqemu;


if(!$ENV{NETBOOT}) {
	# LiveCD needs confirmation for reboot
	waitgoodimage(360);
	waitidle(99);
	sendkey $cmd{"rebootnow"};
	sleep 11; # give some time for going down but not for booting up much
	# workaround:
	# force eject+reboot as it often fails in qemu/kvm
	qemusend "eject -f ide1-cd0";
	sleep 1;
	# hard reset (same as physical reset button on PC)
	qemusend "system_reset";
	sleep 50;
	qemusend "mouse_move 1000 1000"; # move mouse off screen again
}

1;

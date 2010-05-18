#!/usr/bin/perl -w
use strict;
use bmwqemu;

if($ENV{NETBOOT}) {
	waitinststage "grub|automaticconfiguration", 3000;
	sendkey "ret"; # avoid timeout for booting to HDD
	sleep 3;
} else {
	# LiveCD needs confirmation for reboot
	waitinststage("rebootnow", 790);
	sendkey $cmd{"rebootnow"};
	# no grub visible on proper first boot because of kexec
	if(0 && !waitinststage "grub") {
		sleep 11; # give some time for going down but not for booting up much
		# workaround:
		# force eject+reboot as it often fails in qemu/kvm
		qemusend "eject -f ide1-cd0";
		sleep 1;
		# hard reset (same as physical reset button on PC)
		qemusend "system_reset";
	}
	waitinststage "automaticconfiguration";
}
waitinststage "automaticconfiguration", 70;
qemusend "mouse_move 1000 1000"; # move mouse off screen again

1;

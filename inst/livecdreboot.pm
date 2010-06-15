#!/usr/bin/perl -w
use strict;
use bmwqemu;

if(!$ENV{LIVECD}) {
	set_ocr_rect(255,420,530,115);
	{
		local $ENV{SCREENSHOTINTERVAL}=5;
		waitinststage "grub|splashscreen|automaticconfiguration", 3000;
	}
	set_ocr_rect();
	if(waitinststage "grub", 1) {
		sendkey "ret"; # avoid timeout for booting to HDD
	}
	qemusend "eject ide1-cd0";
	sleep 3;
} else {
	set_ocr_rect(245,440,530,100);
	# LiveCD needs confirmation for reboot
	{
		local $ENV{SCREENSHOTINTERVAL}=5;
		waitinststage("rebootnow", 1500);
	}
	set_ocr_rect();
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
mousemove_raw(0x7fff,0x7fff); # move mouse off screen again
mousemove_raw(0x7fff,0x7fff); # work around no reaction on first move
local $ENV{SCREENSHOTINTERVAL}=$ENV{SCREENSHOTINTERVAL}*3;
if(!$ENV{GNOME}) {
	# read sub-stages of automaticconfiguration 
	set_ocr_rect(240,256,530,100);
	waitinststage "users|booted", 180;
	set_ocr_rect();
} else {
	sleep 50; # time for fast-forward
}

1;

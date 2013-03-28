use strict;
use base "installstep";
use bmwqemu;

sub run()
{ my $self=shift;
if(!$ENV{LIVECD}) {
	set_ocr_rect(255,420,530,115);
	{
		if($ENV{XDEBUG} && waitinststage("the-system-will-reboot-now", 3000, 1)) {
			sendkey "alt-s";
			sendkey "ctrl-alt-f2";
			if(!$ENV{NET}) {
				script_run "dhcpcd eth0";
				#ifconfig eth0 10.0.2.15
				#route add default gw 10.0.2.2
				sleep 20;
			}
			script_run "mount /dev/vda2 /mnt";
			script_run "chroot /mnt";
			script_run "echo nameserver 213.133.99.99 > /etc/resolv.conf";
			script_run "wget www3.zq1.de/bernhard/linux/xdebug";
			script_run "sh -x xdebug";
			sleep 99;
			sendkey "ctrl-d";
			script_run "umount /mnt";
			waitidle;
			sleep 20;
			sendkey "ctrl-alt-f7";
			sleep 5;
			sendkey "alt-o";
		}
		local $ENV{SCREENSHOTINTERVAL}=5;
		waitinststage "bootloader|splashscreen|automaticconfiguration|booted", 3000;
		if($ENV{UPGRADE}) {
			sendkey "alt-n"; # ignore repos dialog
			waitstillimage(6,60);
		}
	}
	set_ocr_rect();
	if(waitinststage "bootloader", 1) {
		sendkey "ret"; # avoid timeout for booting to HDD
	}
	qemusend "eject ide1-cd0";
	sleep 3;
	# workaround key trust bug http://openqa.opensuse.org/viewimg/opensuse/testresults/openSUSE-NET-i586-Build0002-lxde/timeout-05.png
	#for(1..4){sendkey "alt-t"} sleep 10;
	if($ENV{ENCRYPT}) {
		waitstillimage(11,180);
		sendpassword(); # enter PW at boot
		sendkey "ret";
	}
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
	if(0 && !waitinststage "bootloader") {
#	if(1 || !waitinststage "bootloader") {
		sleep 11; # give some time for going down but not for booting up much
		# workaround:
		# force eject+reboot as it often fails in qemu/kvm
		qemusend "eject -f ide1-cd0";
		sleep 1;
		# hard reset (same as physical reset button on PC)
		qemusend "system_reset";
	}
}
#if($ENV{RAIDLEVEL} && !$ENV{LIVECD}) { do "$scriptdir/workaround/656536.pm" }
#waitinststage "automaticconfiguration", 70;
mouse_hide();
local $ENV{SCREENSHOTINTERVAL}=$ENV{SCREENSHOTINTERVAL}*3;
if(!$ENV{GNOME}) {
	# read sub-stages of automaticconfiguration 
	set_ocr_rect(240,256,530,100);
	waitinststage "users|booted", 180;
	set_ocr_rect();
	my $img=getcurrentscreenshot();
        my $ocr=ocr::get_ocr($img, "-l 200", [250,100,600,500]);
	diag "post-install-ocr: $ocr";
        if($ocr=~m/Installation of package .* failed/i or waitimage("install-failed", 1)) {
		sendkeyw "alt-d"; # see details of failure
		if(1) { # ignore
			$self->take_screenshot; sleep 2;
			sendkeyw "alt-i";
			sendkey "ret";
			waitstillimage(50,900);
		} else {		
			alarm 3; # end here as we can not continue
		}
	}
} else {
	sleep 50; # time for fast-forward
}

}

1;

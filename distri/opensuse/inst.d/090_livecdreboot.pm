use strict;
use base "installstep";
use bmwqemu;

sub run() { 
	my $self=shift;
	{
		local $ENV{SCREENSHOTINTERVAL}=5;
		waitforneedle("rebootnow", 1500);
	}
	if(!$ENV{LIVECD}) {
		if($ENV{XDEBUG} && waitforneedle("the-system-will-reboot-now", 3000)) {
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
		if($ENV{UPGRADE}) {
			sendkey "alt-n"; # ignore repos dialog
			waitstillimage(6,60);
		}
		waitforneedle("reboot-after-installation", 100);
		if(checkneedle("inst-bootmenu", 1) || checkneedle("grub2", 1)) {
			sendkey "ret"; # avoid timeout for booting to HDD
		}
		qemusend "eject ide1-cd0";
		sleep 3;
		if($ENV{ENCRYPT}) {
			waitstillimage(11,180);
			sendpassword(); # enter PW at boot
			sendkey "ret";
		}
	} else {
		# LiveCD needs confirmation for reboot
		sendkey $cmd{"rebootnow"};
		# no grub visible on proper first boot because of kexec
		if(0 && !waitforneedle("bootloader")) {
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
}

1;

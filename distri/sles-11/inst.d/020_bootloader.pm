use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	unless($ENV{'HW'}) {
		waitinststage("syslinux-bootloader", 30); # wait anim
	}
	else {
		waitcolor([[0,0.3],[0.35,0.6],[0,0.3]], 160); # wait for green
		sleep 15;
	}

	if($ENV{ZDUP} || $ENV{WDUP}) {
		qemusend "eject -f ide1-cd0";
		qemusend "system_reset";
		sleep 10;
		sendkey "ret"; # boot
		return;
	}

	# install
	if($ENV{GFXBOOT}) {
		sendkey "down"; # install
	} else {
		sendkey "esc";
		sleep 1;
		sendkey "ret";
		sleep 25;
		if($ENV{HW}) {
			for(1..10) {
				sendkey "backspace";
				sleep 1;
			}
		}
		my $args="initrd=initrd,08000600.spl splash=silent vga=0x314";
		$args.=" console=ttyS0,115200 console=tty"; # to get crash dumps as text
		$args.=" loglevel=9"; # more debug output
		if($ENV{AUTOYAST}) {
			$args.=" netsetup=dhcp,all autoyast=$ENV{AUTOYAST}";
		}
		if(0 && $ENV{RAIDLEVEL}) {
			$args.=" dud=ftp://metcalf.suse.de/dud/bl insecure=1";
		}
		sendautotype "linux $args";
	}
	sendkey "ret";
	qemusend "boot_set c"; # boot from HDD next time
	if($ENV{'HW'}) {
		# give grub time to start loading kernel
		sleep 40;
	}
	if($ENV{GFXBOOT}) {
		waitimage('bootloader-loadkernel', 130, 'ds');
	}
	else {
		#invalid with new waitcolor: #waitcolor('green', 130, 0.10, 0.90);
		waitcolor([[0,0.3],[0.1,0.9],[0,0.3]], 160); # wait for green instead of black
	}
}

1;

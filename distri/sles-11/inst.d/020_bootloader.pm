use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitinststage("syslinux-bootloader", 30); # wait anim

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
		sendkey "ret";
		sleep 3;
		my $args="initrd=initrd,08000600.spl splash=silent vga=0x314";
		$args.=" console=ttyS0 console=tty"; # to get crash dumps as text
		$args.=" loglevel=9"; # more debug output
		if(0 && $ENV{RAIDLEVEL}) {
			$args.=" dud=ftp://metcalf.suse.de/dud/bl insecure=1";
		}
		sendautotype "linux $args";
	}
	sendkey "ret";
	qemusend "boot_set c"; # boot from HDD next time
}

1;

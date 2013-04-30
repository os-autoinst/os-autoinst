use base "basetest";
use strict;
use bmwqemu;
use Time::HiRes qw(sleep);

sub run()
{
	unless($ENV{'HW'}) {
		waitforneedle("syslinux-bootloader", 15); # wait bootloader menu
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
		sleep 5;
		if($ENV{HW}) {
			for(1..10) {
				sendkey "backspace";
				sleep 0.2;
			}
		}
		# Force 1024x768 mode
		my $args="initrd=initrd,10240768.spl splash=silent vga=0x317 nomodeset";
		$args.=" console=ttyS0,115200 console=tty"; # to get crash dumps as text
		$args.=" loglevel=9"; # more debug output
		if($ENV{AUTOYAST}) {
			$args.=" netsetup=dhcp,all autoyast=$ENV{AUTOYAST}";
		}
		if(0 && $ENV{RAIDLEVEL}) {
			$args.=" dud=ftp://metcalf.suse.de/dud/bl insecure=1";
		}
		if($ENV{NET}) {
			my $neturl = "http://autoinst.qa.suse.de:8080/repo/"; #move this to config

			my $ver=$ENV{ISO};
			$ver=~s#.*/##;
			$ver=~s#\.iso$##;
			$ver=~s#-Media1$##;
			my $dvd_ver = $ver;
			$dvd_ver=~s/NET/DVD/;
			my $url_ver = $dvd_ver;
			$url_ver=~s/-Build\d\d\d\d//;

			my $url_res = get($neturl.$url_ver."/media.1/build") || ''; 
			chomp($url_res);
			if($url_res ne $dvd_ver) {
				mydie("NETINST FAILED: Invalid repo\nURL: ".$neturl.$url_ver."/media.1/build\nEXPECTED: $dvd_ver\nGOT: $url_res\n");
			}
			$args .= " install=".$neturl.$url_ver;
		}
		sendautotype "linux $args";
	}
	sendkey "ret";
	qemusend "boot_set c"; # boot from HDD next time

	if($ENV{'HW'}) {
		# give grub time to start loading kernel
		sleep 40;
	} else {
		waitforneedle('bootloader-loadkernel', 30);
	}
}

1;

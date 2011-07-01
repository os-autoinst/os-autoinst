use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitinststage("syslinux-bootloader", 20); # wait anim
	# install
	sendkey "down";
	sleep 1;
	sendkey "ret";
}

1;

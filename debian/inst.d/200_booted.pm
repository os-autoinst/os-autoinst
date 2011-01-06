use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitinststage("debian-booted-gdm", 100);
	sendkey "ret"; # confirm reboot
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# speed up main install video
	local $ENV{SCREENSHOTINTERVAL}=5;
	waitinststage("debian-grubinstall", 3600);
	sendkey "ret"; # install grub into MBR
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# boot
	sendkey "1"; # boot Entry 1 = default FreeBSD
	sleep 15;
}

1;

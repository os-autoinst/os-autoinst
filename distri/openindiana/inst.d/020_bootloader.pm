use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# boot
	sendkey "ret";
	sleep 7;
}

1;

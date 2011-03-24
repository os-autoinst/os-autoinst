use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# boot
	sendautotype "linux\n";
	waitidle;
}

1;

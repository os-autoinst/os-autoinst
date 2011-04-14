use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendkey "down"; # Standard
	sendkey "ret"; # select
}

1;

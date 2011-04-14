use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(20); # boot up
	sendkey "ret"; # country=USA
}

1;

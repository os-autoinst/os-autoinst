use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "ret"; # timezone
}

1;

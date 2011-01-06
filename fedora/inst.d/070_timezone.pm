use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "alt-n"; # timezone
}

1;

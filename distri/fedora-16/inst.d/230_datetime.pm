use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "alt-f"; # forward "Date and Time"
}

1;

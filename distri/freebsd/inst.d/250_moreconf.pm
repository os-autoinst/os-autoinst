use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "ret"; # mouse
	sleep 3;
	sendkey "tab"; sendkey "ret"; # dont browse package collection
}

1;

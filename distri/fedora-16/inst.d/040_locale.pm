use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 10;
	waitidle;
	sendkey "ret"; # lang
	waitidle;
	sendkey "ret"; # keyboard
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitinststage("debian-popconconf", 100);
	sendkey "ret"; # no popcon
	sleep 5; waitidle;
}

1;

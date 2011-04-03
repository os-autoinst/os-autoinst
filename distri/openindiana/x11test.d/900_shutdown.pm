use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 2;
	qemusend "system_powerdown";
	sleep 2;
	sendkey "alt-s";
	sleep 4;
	waitidle;
	qemusend "quit";
}

1;

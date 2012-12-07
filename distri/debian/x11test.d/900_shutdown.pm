use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 2;
	sendkey "ctrl-alt-f2";sleep 3;
	qemusend "system_powerdown";
	sleep 2;
	sendkey "alt-s";
}

1;

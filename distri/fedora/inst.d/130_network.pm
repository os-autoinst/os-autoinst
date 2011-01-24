use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "alt-o"; # use eth0
	waitidle;
	sendkey "alt-c"; # close popup
	sleep 12; # network conf time
	waitidle;
}

1;

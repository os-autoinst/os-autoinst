use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	# do not send
	sendkey "alt-f"; # finish "Hardware Profile"
	sleep 2;
	sendkey "alt-n"; # dont reconsider sending
}

1;

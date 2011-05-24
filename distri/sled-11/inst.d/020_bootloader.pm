use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 6; # wait anim
	# install
	sendkey "down";
	sendkey "ret";
	sleep 29;
	waitidle;
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# default = system+desktop
	sendkey "ret"; # accept
}

1;

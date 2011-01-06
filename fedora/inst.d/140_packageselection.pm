use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# default = Graphical Desktop
	sendkey "alt-n"; # accept
	# this starts install
}

1;

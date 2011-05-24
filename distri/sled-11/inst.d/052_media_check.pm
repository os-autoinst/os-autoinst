use strict;
use base "basetest";
use bmwqemu;

sub run()
{
	# skip media check
	sendkeyw $cmd{"next"};
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitinststage("booted", 60);
}

1;

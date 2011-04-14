use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendautotype("shutdown -p now\n"); # with powerdown
}

1;

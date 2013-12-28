use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendautotype("shutdown -h now\n"); # with powerdown
}

1;

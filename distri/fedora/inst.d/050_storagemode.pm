use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "alt-n"; # basic storage devs
	waitidle;
	sendkey "alt-t"; # re-initialize all
}

1;

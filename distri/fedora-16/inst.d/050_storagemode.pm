use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	mousemove_raw(0x7fff,0x7fff);
	sendkey "alt-n"; # basic storage devs
	waitidle;
	sendkey "alt-y"; # re-initialize all
}

1;

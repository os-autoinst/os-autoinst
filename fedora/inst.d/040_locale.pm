use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 10;
	waitidle;
	mousemove_raw(0x7fff,0x7fff);
	sendkey "alt-n"; # welcome screen
	waitidle;
	sendkey "alt-n"; # lang
	waitidle;
	sendkey "alt-n"; # keyboard
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitinststage("postreboot", 100);
	sendkey "alt-f"; # forward welcome
	waitidle;
	sendkey "alt-f"; # forward license
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitstillimage(20, 100);
	sendkeyw "alt-f"; # forward welcome
	sendkeyw "alt-f"; # forward license
}

1;

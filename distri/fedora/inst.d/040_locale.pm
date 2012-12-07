use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 10;
	waitidle;
	mouse_hide;
	sendkey "alt-n"; # welcome screen
	waitidle;
	sendkey "alt-n"; # lang
	waitidle;
	sendkey "alt-n"; # keyboard
}

1;

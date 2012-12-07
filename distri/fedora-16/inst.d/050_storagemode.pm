use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	mouse_hide;
	sendkey "alt-n"; # basic storage devs
	waitidle;
	sendkey "alt-y"; # re-initialize all
}

1;

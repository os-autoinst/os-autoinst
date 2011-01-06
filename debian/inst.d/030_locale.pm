use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(10); # boot up
	sendkey "ret"; # lang
	sendkey "ret"; # country
	sendkey "ret"; # keymap
}

1;

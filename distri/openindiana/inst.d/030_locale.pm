use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(20); # boot up
	sendkey "ret"; # keymap 47=US
	sendkey "ret"; # lang 7=EN
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendkey "ctrl-alt-f7"; sleep 4;
	sendautotype("$username\n");
	waitidle;
	sendpassword();
	sendkey("ret");
	waitinststage("desktop", 50);
	waitidle(70);
	sleep 6;
}

1;

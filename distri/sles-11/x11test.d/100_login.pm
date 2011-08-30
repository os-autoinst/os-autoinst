use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendautotype("$username\n");
	waitidle;
	sendpassword();
	sendkey("ret");
	waitinststage("desktop", 50);
	waitidle(70);
	sleep 6;
}

1;

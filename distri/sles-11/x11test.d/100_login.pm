use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendautotype("$username\n");
	waitidle;
	sendpassword();
	sendkey("ret");
	sleep 6;
	waitidle(70);
}

1;

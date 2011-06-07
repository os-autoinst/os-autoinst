use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendautotype("$username\n");
	waitidle;
	sendpassword();
	sendkey("ret");
	waitidle;
}

1;

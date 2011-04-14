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
	sendkey("ctrl-l");
	script_run("id");
	script_run("su -");
	sendpassword();
	sendkey("ret");
}

1;

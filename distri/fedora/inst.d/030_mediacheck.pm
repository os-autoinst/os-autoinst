use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "tab"; # skip media check
	sendkey "ret";
}

1;

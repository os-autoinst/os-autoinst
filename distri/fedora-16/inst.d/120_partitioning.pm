use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "alt-n"; # overwrite
	waitidle;
	sendkey "alt-w"; # write to disk
	sleep 11; # time to format disks
}

1;

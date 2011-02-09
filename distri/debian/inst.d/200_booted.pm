use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitinststage("debian-booted-gdm", 100);
}

1;

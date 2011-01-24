use strict;
use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};
}

sub run()
{
	sleep 11; # time to load kernel+initrd
	sendkey "esc";
}

1;

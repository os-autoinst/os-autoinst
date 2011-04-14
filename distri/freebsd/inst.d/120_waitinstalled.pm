use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# speed up main install video
	local $ENV{SCREENSHOTINTERVAL}=5;
	waitinststage("install-done", 3600);
	sendkey "ret";
}

1;

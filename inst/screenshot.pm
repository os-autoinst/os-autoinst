#!/usr/bin/perl -w
use strict;
use warnings;
use bmwqemu;
use threads;

sub screenshotsub
{
	while(qemualive() && sleep($ENV{SCREENSHOTINTERVAL}||5)) {
		bmwqemu::take_screenshot();
	}
}

sleep 3; # wait until BIOS is gone
our $screenshotthr = threads->create(\&screenshotsub);

1;

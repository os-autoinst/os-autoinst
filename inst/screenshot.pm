#!/usr/bin/perl -w
use strict;
use warnings;
use Time::HiRes "sleep";
use bmwqemu;
use threads;

sub screenshotsub
{
	while(bmwqemu::alive() && sleep($ENV{SCREENSHOTINTERVAL}||5)) {
		bmwqemu::take_screenshot('q');
	}
}

sleep 3; # wait until BIOS is gone
our $screenshotthr = threads->create(\&screenshotsub);

1;

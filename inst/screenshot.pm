#!/usr/bin/perl -w
use strict;
use warnings;
use bmwqemu;
use Time::HiRes "sleep";
use threads;

sub screenshotsub
{
	while(qemualive() && sleep($ENV{SCREENSHOTINTERVAL}||5)) {
		take_screenshot();
	}
}

sleep 2; # wait until BIOS is gone
our $screenshotthr = threads->create(\&screenshotsub);

#my $pid=fork();
#die "fork failed" if(!defined($pid));
#if($pid==0) {
	#screenshotsub();
#	exit 0;
#}

1;

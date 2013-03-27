#!/usr/bin/perl -w
use strict;
use warnings;
use Time::HiRes qw( sleep gettimeofday );
use bmwqemu;
use threads;

sub screenshotsub
{
        my $interval = $ENV{SCREENSHOTINTERVAL}||5;
       	while(bmwqemu::alive()) {
	  my ($s1, $ms1) = gettimeofday();
	  bmwqemu::take_screenshot('q');
	  my ($s2, $ms2) = gettimeofday();
	  my $rest = $interval - ($s2*1000.+$ms2/1000.-$s1*1000.-$ms1/1000.)/1000.;
	  sleep($rest) if ($rest > 0);
	}
}

sleep 3; # wait until BIOS is gone
our $screenshotthr = threads->create(\&screenshotsub);

1;

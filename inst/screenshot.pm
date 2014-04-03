#!/usr/bin/perl -w
use strict;
use warnings;
use Time::HiRes qw( sleep gettimeofday );
use bmwqemu;
use threads;
use cv;

sub screenshotsub {

    # cv::init called from bmwqemu
    require tinycv;
    my $interval = $ENV{SCREENSHOTINTERVAL} || .5;
    while ( bmwqemu::alive() ) {
        my ( $s1, $ms1 ) = gettimeofday();
        bmwqemu::take_screenshot('q');
        my ( $s2, $ms2 ) = gettimeofday();
        my $rest = $interval - ( $s2 - $s1 ) - ( $ms2 - $ms1 ) / 1e6;
        sleep($rest) if ( $rest > 0 );
        for my $t ( threads->list() ) {
            if ( $t->error() ) {
                printf "thread %d had an error: %d\n", $t->error();
            }
        }
    }
}

threads->create( \&screenshotsub );

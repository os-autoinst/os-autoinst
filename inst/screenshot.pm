#!/usr/bin/perl -w

package inst::screenshot;

require Carp;
use strict;
use warnings;
use Time::HiRes qw( sleep gettimeofday );
use bmwqemu;
use threads;
use cv;


my $backend;

sub screenshotsub {

    # cv::init called from bmwqemu
    require tinycv;
    my $interval = $bmwqemu::vars{SCREENSHOTINTERVAL} || .5;
    while ( $backend->alive() ) {
        my ( $s1, $ms1 ) = gettimeofday();
        my $img = $backend->screendump();
        $img = $img->scale( 1024, 768 );

        bmwqemu::enqueue_screenshot($img);

        my ( $s2, $ms2 ) = gettimeofday();
        my $rest = $interval - ( $s2 - $s1 ) - ( $ms2 - $ms1 ) / 1e6;
        sleep($rest) if ( $rest > 0 );
        for my $t ( threads->list() ) {
            if ( $t->error() ) {
                printf "thread %d had an error: %d\n", $t->error();
            }
        }
    }
    print "done\n";
}

sub start_screenshot_thread($) {
    $backend = shift;
    unless ( $backend->alive() ) {
        Carp::carp "make sure to only init the screenshot thread once the backend is alive";
    }
    threads->create( \&screenshotsub );
}

1;

# vim: set sw=4 et:

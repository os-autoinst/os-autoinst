#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::Warnings;
use backend::baseclass;
use POSIX 'tzset';

BEGIN {
    unshift @INC, '..';
}

# make the test time-zone neutral
$ENV{TZ} = 'UTC';
tzset;

my $baseclass = backend::baseclass->new();

subtest 'format_vtt_timestamp' => sub {
    my $timestamp = 1543917024;

    $baseclass->{video_frame_number} = 0;
    is($baseclass->format_vtt_timestamp($timestamp),
        "\n0\n00:00:00.000 --> 00:00:00.041\n[2018-12-04T09:50:24.000]\n",
        'frame number 0'
    );

    $baseclass->{video_frame_number} = 1;
    is($baseclass->format_vtt_timestamp($timestamp),
        "\n1\n00:00:00.041 --> 00:00:00.083\n[2018-12-04T09:50:24.000]\n",
        'frame number 1'
    );
};

done_testing;

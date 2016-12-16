#!/usr/bin/perl
# Do not add to makefile.am

use strict;
use warnings;
use Test::More;

use Try::Tiny;
use File::Basename;
use File::Path qw(make_path remove_tree);
use Cwd;


BEGIN {
    unshift @INC, '..';
}

use OpenQA::Benchmark::Stopwatch;


# optional but very useful
eval 'use Test::More::Color';                 ## no critic
eval 'use Test::More::Color "foreground"';    ## no critic

use cv;

cv::init();
require tinycv;

my $data_dir = dirname(__FILE__) . '/data/';
my $img1     = tinycv::read($data_dir . 'xorg_vt-Xorg-20140729.png');
my $ppm      = $img1->ppm_data();
like($ppm, qr/^P6\s1024 768\s255/, 'is a ppm');
my $img2 = tinycv::from_ppm($ppm);

$img1->write('test1.png');
$img2->write('test2.png');
is(1000000, $img1->similarity($img2));

done_testing();

# vim: set sw=4 et:

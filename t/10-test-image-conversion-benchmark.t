#!/usr/bin/perl
# Do not add to makefile.am

use strict;
use warnings;
use Test::More;
use Test::Warnings;

use Try::Tiny;
use File::Basename;
use File::Path qw(make_path remove_tree);
use File::Temp 'tempfile';
use Cwd;


BEGIN {
    unshift @INC, '..';
}

use OpenQA::Benchmark::Stopwatch;


# optional but very useful
eval 'use Test::More::Color';                 ## no critic
eval 'use Test::More::Color "foreground"';    ## no critic

use needle;
use cv;

cv::init();
require tinycv;


my ($res, $needle, $image, $cand, $img_src);

my $data_dir   = 't/data';
my $result_dir = "$data_dir/results";

make_path($result_dir);

opendir(DIR, $data_dir) or die("Cannot read directories: $data_dir");

my @all_images = grep { /\.png$/ } readdir DIR;

my $watch = OpenQA::Benchmark::Stopwatch->new();
$watch->start();

foreach my $img_src (@all_images) {
    my (undef, $filename) = tempfile('test-XXXXX', DIR => $result_dir, SUFFIX => $img_src, OPEN => 0);
    $image = tinycv::read($data_dir . '/' . $img_src);
    if ($image) {
        $image->write($filename);
    }
    ok(-e $filename, "Passed $filename");
    $watch->lap("$img_src");
}

remove_tree($result_dir, {verbose => 1});

$watch->stop();
print $watch->summary();


done_testing();

# vim: set sw=4 et:

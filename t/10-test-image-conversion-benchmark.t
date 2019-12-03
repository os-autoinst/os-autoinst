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


use OpenQA::Benchmark::Stopwatch;


# optional but very useful
eval 'use Test::More::Color';
eval 'use Test::More::Color "foreground"';

use needle;
use cv;

cv::init();
require tinycv;


my ($res, $needle, $image, $cand, $img_src);

my $data_dir   = 't/data';
my $result_dir = "$data_dir/results";

make_path($result_dir);

opendir(my $dir, $data_dir) or die("Cannot read directories: $data_dir");

my @all_images = grep { /\.png$/ } readdir $dir;

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

#!/usr/bin/perl
use Test::Most;
use Mojo::Base -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib", "$Bin/../tools/lib";
use OpenQA::Test::Isolation qw(setup_isolated_workdir);
use OpenQA::Test::TimeLimit '30';
use Test::Warnings ':report_warnings';

use File::Basename;
use File::Path qw(make_path remove_tree);
use File::Temp 'tempfile';
use Cwd;
use Mojo::File qw(path);
use OpenQA::Benchmark::Stopwatch;
use needle;
use cv;

cv::init();
require tinycv;


my ($res, $needle, $image, $cand, $img_src);

my $data_dir = "$Bin/data";
my ($isolation_guard, $result_dir) = setup_isolated_workdir();

opendir my $dir, $data_dir or die "Cannot read directories: $data_dir";

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

$watch->stop();
print $watch->summary();


done_testing();

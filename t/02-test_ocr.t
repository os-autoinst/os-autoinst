#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use Test::Output;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings ':report_warnings';
use File::Which 'which';
use File::Basename;

BEGIN {
    $bmwqemu::vars{DISTRI} = 'unicorn';
    $bmwqemu::vars{CASEDIR} = '/var/lib/empty';
    $bmwqemu::vars{NEEDLES_DIR} = dirname(__FILE__) . '/data';
}

use needle;
use cv;
use ocr;

cv::init();
require tinycv;

unless (which('tesseract')) {
    plan skip_all => 'No tesseract installed';    # uncoverable statement
    exit(0);    # uncoverable statement
}

stderr_like { needle::init } qr/loaded.*needles/, 'log output for needle init';
my $img1 = tinycv::read(needle::needles_dir() . '/bootmenu.test.png');
my $needle = needle->new('bootmenu-ocr.ref.json');
my $res;
$res = $img1->search($needle);
ok(defined $res, 'ocr match 1');

my $ocr;
for my $area (@{$res->{needle}->{area}}) {
    next unless $area->{type} eq 'ocr';
    $ocr .= ocr::tesseract($img1, $area);
}

ok defined $ocr, 'OCR area found' and
  ok($ocr =~ /Memory Test.*Video Mode/s, 'multiple OCR regions');

done_testing;


END {
    unlink 'ocr.png';
    unlink 'tesseract_opencl_profile_devices.dat';
}

#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Which 'which';
use File::Basename;

BEGIN {
    unshift @INC, '..';
    $bmwqemu::vars{DISTRI}  = "unicorn";
    $bmwqemu::vars{CASEDIR} = "/var/lib/empty";
}

use needle;
use cv;
use ocr;

cv::init();
require tinycv;

unless (which('tesseract')) {
    plan skip_all => 'No tesseract installed';
    exit(0);
}

my ($res, $needle, $img1);

my $data_dir = dirname(__FILE__) . '/data/';
$bmwqemu::vars{PRJDIR} = $data_dir;
$img1 = tinycv::read($data_dir . "bootmenu.test.png");

$needle = needle->new($data_dir . "bootmenu-ocr.ref.json");
$res    = $img1->search($needle);
ok(defined $res, "ocr match 1");

my $ocr;
for my $a (@{$res->{needle}->{area}}) {
    next unless $a->{type} eq 'ocr';
    $ocr .= ocr::tesseract($img1, $a);
}

ok($ocr =~ /Memory Test.*Video Mode/s, "multiple OCR regions");
done_testing;

# vim: set sw=4 et:

#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Which qw(which);

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
plan tests => 2;

my ($res, $needle, $img1);

$img1 = tinycv::read("data/bootmenu.test.png");

$needle = needle->new("data/bootmenu-ocr.ref.json");
$res    = $img1->search($needle);
ok(defined $res, "ocr match 1");

my $ocr;
for my $a (@{$res->{needle}->{area}}) {
    next unless $a->{type} eq 'ocr';
    $ocr .= ocr::tesseract($img1, $a);
}

ok($ocr =~ /Memory Test.*Video Mode/s, "multiple OCR regions");
done_testing();

# vim: set sw=4 et:

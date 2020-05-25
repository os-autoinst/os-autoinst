#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Output;
use Test::Warnings;
use File::Which 'which';
use File::Basename;

BEGIN {
    $bmwqemu::vars{DISTRI}      = 'unicorn';
    $bmwqemu::vars{CASEDIR}     = '/var/lib/empty';
    $bmwqemu::vars{NEEDLES_DIR} = dirname(__FILE__) . '/data';
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

stderr_like { needle::init } qr/loaded.*needles/, 'log output for needle init';
my $img1   = tinycv::read(needle::needles_dir() . '/bootmenu.test.png');
my $needle = needle->new('bootmenu-ocr.ref.json');
my $res;
stderr_like { $res = $img1->search($needle) } qr/Tesseract.*OCR/, 'log output for OCR';
ok(defined $res, 'ocr match 1');

my $ocr;
for my $area (@{$res->{needle}->{area}}) {
    next unless $area->{type} eq 'ocr';
    stderr_like { $ocr .= ocr::tesseract($img1, $area) } qr/Tesseract.*OCR/, 'log output for tesseract call';
}

ok($ocr =~ /Memory Test.*Video Mode/s, 'multiple OCR regions');
done_testing;

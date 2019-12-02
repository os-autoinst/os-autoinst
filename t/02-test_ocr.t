#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Warnings;
use File::Which 'which';
use File::Basename;
use FindBin '$Bin';
use lib "$Bin/..";

BEGIN {
    $bmwqemu::vars{DISTRI}      = 'unicorn';
    $bmwqemu::vars{CASEDIR}     = '/var/lib/empty';
    $bmwqemu::vars{NEEDLES_DIR} = 'data';
}

use needle;
use cv;
use ocr;

chdir $Bin;

cv::init();
require tinycv;

unless (which('tesseract')) {
    plan skip_all => 'No tesseract installed';
    exit(0);
}

needle::init;

my $img1   = tinycv::read("$needle::needledir/bootmenu.test.png");
my $needle = needle->new('bootmenu-ocr.ref.json');
my $res    = $img1->search($needle);
ok(defined $res, 'ocr match 1');

my $ocr;
for my $area (@{$res->{needle}->{area}}) {
    next unless $area->{type} eq 'ocr';
    $ocr .= ocr::tesseract($img1, $area);
}

ok($ocr =~ /Memory Test.*Video Mode/s, "multiple OCR regions");
done_testing;

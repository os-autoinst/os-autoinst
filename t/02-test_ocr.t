#!/usr/bin/perl -w -I..

use strict;
use Test::Simple tests => 2;

BEGIN {
    $bmwqemu::vars{DISTRI}  = "unicorn";
    $bmwqemu::vars{CASEDIR} = "/var/lib/empty";
}

use needle;
use cv;
use ocr;

cv::init();
require tinycv;

my ( $res, $needle, $img1 );

$img1 = tinycv::read("data/bootmenu.test.png");

$needle = needle->new("data/bootmenu-ocr.ref.json");
$res    = $img1->search($needle);
ok( defined $res, "ocr match 1" );

my $ocr;
for my $a ( @{ $res->{'needle'}->{'area'} } ) {
    next unless $a->{'type'} eq 'ocr';

    #    my $ocr=ocr::get_ocr($img1, "-l 0",
    #	    [ $a->{'xpos'}, $a->{'ypos'}, $a->{'width'}, $a->{'height'} ]);

    $ocr .= ocr::tesseract( $img1, $a );
}

ok( $ocr =~ /Memory Test.*Video Mode/s, "multiple OCR regions" );
# vim: set sw=4 et:

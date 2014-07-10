#!/usr/bin/perl -w -I..

use strict;
use Test::More tests => 24;

BEGIN {
    $bmwqemu::vars{DISTRI}  = "unicorn";
    $bmwqemu::vars{CASEDIR} = "/var/lib/empty";
}

use needle;
use cv;
use Data::Dumper;

cv::init();
require tinycv;

my ( $res, $needle, $img1, $cand );

$img1 = tinycv::read("data/bootmenu.test.png");

$needle = needle->new("data/bootmenu.ref.json");

$res = $img1->search($needle);

ok( defined $res, "match with exclude area" );

( $res, $cand ) = $img1->search($needle);
ok( defined $res,                           "match in array context" );
ok( $res->{'ok'},                           "match in array context ok == 1" );
ok( $res->{'area'}->[-1]->{result} eq 'ok', "match in array context result == ok" );
ok( !defined $cand,                         "candidates must be undefined" );

$needle = needle->new("data/bootmenu-fail.ref.json");
$res    = $img1->search($needle);
ok( !defined $res, "no match" );

( $res, $cand ) = $img1->search($needle);
ok( !defined $res, "no match in array context" );
ok( defined $cand && ref $cand eq 'ARRAY', "candidates must be array" );

$img1   = tinycv::read("data/welcome.test.png");
$needle = needle->new("data/welcome.ref.json");
$res    = $img1->search($needle);
ok( defined $res, "match with different art" );

$img1   = tinycv::read("data/kde.test.png");
$needle = needle->new("data/kde.ref.json");
$res    = $img1->search($needle);
ok( !defined $res, "no match with different art" );

$img1   = tinycv::read("data/console.test.png");
$needle = needle->new("data/console.ref.json");
$res    = $img1->search($needle);
ok( !defined $res, "no match different console screenshots" );

# XXX TODO -- This need to be fixed.
# $img1   = tinycv::read("data/font-kerning.test.png");
# $needle = needle->new("data/font-kerning.ref.json");
# $res    = $img1->search($needle);
# ok( defined $res, "match when the font kerning change" );

$img1   = tinycv::read("data/instdetails.test.png");
$needle = needle->new("data/instdetails.ref.json");
$res    = $img1->search($needle);
ok( !defined $res, "no match different perform installation tabs" );

# Check that if the margin is missing from JSON, is set in the hash
$img1   = tinycv::read("data/uefi.test.png");
$needle = needle->new("data/uefi.ref.json");
ok( $needle->{area}->[0]->{margin} == 300, "search margin have the default value");
$needle->{area}->[0]->{margin} = 50;
$res    = $img1->search($needle);
ok( !defined $res, "no found a match for an small margin" );

# Check that if the margin is set in JSON, is set in the hash
$img1   = tinycv::read("data/uefi.test.png");
$needle = needle->new("data/uefi-margin.ref.json");
ok( $needle->{area}->[0]->{margin} == 100, "search margin have the defined value");
$res    = $img1->search($needle);
ok( defined $res, "found match for a large margin" );
ok( $res->{area}->[0]->{x} == 378 && $res->{area}->[0]->{y} == 221, "mach area coordinates" );

$img1   = tinycv::read("data/zypper_ref.test.png");
$needle = needle->new("data/zypper_ref.ref.json");
ok( $needle->{area}->[0]->{margin} == 300, "search margin have the default value");
$res    = $img1->search($needle);
ok( defined $res, "found a match for 300 margin" );

needle::init("data");
my @alltags = sort keys %needle::tags;

my @needles = @{ needle::tags('FIXME') || [] };
is( @needles, 4, "four needles found" );
for my $n (@needles) {
    $n->unregister();
}

@needles = @{ needle::tags('FIXME') || [] };
is( @needles, 0, "no needles after unregister" );

for my $n ( needle::all() ) {
    $n->unregister();
}

is_deeply( \%needle::tags, {}, "no tags registered" );

for my $n ( needle::all() ) {
    $n->register();
}

is_deeply( \@alltags, [ sort keys %needle::tags ], "all tags restored" );

$img1 = tinycv::read("data/user_settings-1.png");
my $img2 = tinycv::read("data/user_settings-2.png");
ok( $img1->similarity($img2) > 53, "similarity is too small" );


# vim: set sw=4 et:

#!/usr/bin/perl -w -I..

use strict;
use Test::More tests => 45;

# optional but very useful
eval 'use Test::More::Color';
eval 'use Test::More::Color "foreground"';

BEGIN {
    $bmwqemu::vars{DISTRI}  = "unicorn";
    $bmwqemu::vars{CASEDIR} = "/var/lib/empty";
}

use needle;
use cv;

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

# this test is just asking too much as the screens are very different (SSIM of 87%!)
#$img1   = tinycv::read("data/welcome.test.png");
#$needle = needle->new("data/welcome.ref.json");
#$res    = $img1->search($needle);
#ok( defined $res, "match with different art" );

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
ok( $needle->{area}->[0]->{margin} == 50, "search margin have the default value");
$res    = $img1->search($needle);
ok( !defined $res, "no found a match for an small margin" );

# Check that if the margin is set in JSON, is set in the hash
$img1   = tinycv::read("data/uefi.test.png");
$needle = needle->new("data/uefi-margin.ref.json");
ok( $needle->{area}->[0]->{margin} == 100, "search margin have the defined value");
$res    = $img1->search($needle);
ok( defined $res, "found match for a large margin" );
ok( $res->{area}->[0]->{x} == 378 && $res->{area}->[0]->{y} == 221, "mach area coordinates" );

# This test fails in internal SLE system
$img1   = tinycv::read("data/glibc_i686.test.png");
$needle = needle->new("data/glibc_i686.ref.json");
$res    = $img1->search($needle);
ok( !defined $res, "no found a match for an small margin" );
# We emulate assert_screen "needle", 3;
my $timeout = 3;
for ( my $n = 0 ; $n < $timeout ; $n++ ) {
    my $search_ratio =  1.0 - ($timeout - $n) / ($timeout);
    $res = $img1->search($needle, 0, $search_ratio);
}
ok( defined $res, "found match after timeout" );

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

$img1 = tinycv::read("data/screenlock.test.png");
$needle = needle->new("data/screenlock.ref.json");
$res    = $img1->search($needle);

ok( defined $res, "match screenlock" );

$img1 = tinycv::read("data/desktop-at-first-boot-kde-without-greeter-20140926.test.png");
$needle = needle->new("data/desktop-at-first-boot-kde-without-greeter-20140926.json");
$res    = $img1->search($needle);
ok( !defined $res, "KDE clearly not ready" );

$img1 = tinycv::read("data/yast2_lan-hostname-tab-20140630.test.png");
$needle = needle->new("data/yast2_lan-hostname-tab-20140630.json");
$res    = $img1->search($needle);

ok( defined $res, "hostname is different" );

$img1 = tinycv::read("data/desktop_mainmenu-gnomesled-sles12.test.png");
$needle = needle->new("data/desktop_mainmenu-gnomesled-sles12.json");
$res    = $img1->search($needle);

ok( !defined $res, "the mixer has a hover effect");

$img1 = tinycv::read("data/inst-video-typed-sles12b9.test.png");
$needle = needle->new("data/inst-video-typed-sles12b9.json");
$res    = $img1->search($needle);

ok( !defined $res, "the contrast is just too different");

$img1 = tinycv::read("data/xterm-started-20141204.test.png");
$needle = needle->new("data/xterm-started-20141204.json");
$res    = $img1->search($needle, 0, 0.7);

ok( defined $res, "xterm basically the same");

$img1 = tinycv::read("data/pkcon-proceed-prompt-20141205.test.png");
$needle = needle->new("data/pkcon-proceed-prompt-20141205.json");
$res    = $img1->search($needle, 0, 0.7);

ok( defined $res, "the prompt is the same to the human eye");

$img1 = tinycv::read("data/displaymanager-sle12.test.png");
$needle = needle->new("data/displaymanager-sle12.json");
$res    = $img1->search($needle);

ok( !defined $res, "the headline is completely different");

$img1 = tinycv::read("data/inst-rescuesystem-20141027.test.png");
$needle = needle->new("data/inst-rescuesystem-20141027.json");
$res    = $img1->search($needle);

ok( !defined $res, "different text");

$img1 = tinycv::read("data/inst-welcome-20140902.test.png");
$needle = needle->new("data/inst-welcome-20140902.json");
$res    = $img1->search($needle);

ok( defined $res, "match welcome");

$img1 = tinycv::read("data/confirmlicense-sle12.test.png");
$needle = needle->new("data/confirmlicense-sle12.json");
$res    = $img1->search($needle);

ok( defined $res, "license to confirm");

$img1 = tinycv::read("data/desktop-runner-20140523.test.png");
$needle = needle->new("data/desktop-runner-20140523.json");
$res    = $img1->search($needle);

ok( defined $res, "just some dark shade");

$img1 = tinycv::read("data/accept-ssh-host-key.test.png");
$needle = needle->new("data/accept-ssh-host-key.json");
$res    = $img1->search($needle);

ok( !defined $res, "no match for blinking cursor");

$img1 = tinycv::read("data/xorg_vt-Xorg-20140729.test.png");
$needle = needle->new("data/xorg_vt-Xorg-20140729.json");
$res    = $img1->search($needle);

ok( !defined $res, "the y goes into the line");

$needle = needle->new("data/kde-unselected-20141211.json");
$img1 = tinycv::read("data/kde-unselected-20141211.test.png");
$res    = $img1->search($needle);

ok( defined $res, "match kde is not selected");

# make sure the last area is the click area
is( $res->{area}->[-1]->{w}, 17);
is( $res->{area}->[-1]->{h}, 12);
is( $res->{area}->[-1]->{y}, 260);
is( $res->{area}->[-1]->{x}, 313);

$img1 = tinycv::read("data/other-desktop-dvd-20140904.test.png");
$needle = needle->new("data/other-desktop-dvd-20140904.json");
$res    = $img1->search($needle);

ok( !defined $res, "the hot keys don't match");

# vim: set sw=4 et:

#!/usr/bin/perl

use strict;
use warnings;
use Cwd 'abs_path';
use Test::More;
use Test::Warnings;
use Try::Tiny;
use File::Basename;
use File::Path 'make_path';
use File::Temp 'tempdir';

# optional but very useful
eval 'use Test::More::Color';
eval 'use Test::More::Color "foreground"';

BEGIN {
    unshift @INC, '..';
    $bmwqemu::vars{DISTRI}  = "unicorn";
    $bmwqemu::vars{CASEDIR} = "/var/lib/empty";
    $bmwqemu::vars{PRJDIR}  = dirname(__FILE__);
}

use needle;
use cv;

cv::init();
require tinycv;

my ($res, $needle, $img1, $cand);

my $data_dir = dirname(__FILE__) . '/data/';
$img1 = tinycv::read($data_dir . "bootmenu.test.png");

$needle = needle->new($data_dir . "bootmenu.ref.json");

is($needle->has_tag('inst-bootmenu'), 1, "tag found");
is($needle->has_tag('foobar'),        0, "tag not found");

is($needle->has_property('glossy'), 1, "property found");
is($needle->has_property('dull'),   0, "property not found");

$res = $img1->search($needle);

ok(defined $res, "match with exclude area");

($res, $cand) = $img1->search($needle);
ok(defined $res,                         "match in array context");
ok($res->{ok},                           "match in array context ok == 1");
ok($res->{area}->[-1]->{result} eq 'ok', "match in array context result == ok");
ok(!defined $cand,                       "candidates must be undefined");

$needle = needle->new($data_dir . "bootmenu-fail.ref.json");
$res    = $img1->search($needle);
ok(!defined $res, "no match");

($res, $cand) = $img1->search($needle);
ok(!defined $res, "no match in array context");
ok(defined $cand && ref $cand eq 'ARRAY', "candidates must be array");

# this test is just asking too much as the screens are very different (SSIM of 87%!)
#$img1   = tinycv::read($data_dir . "welcome.test.png");
#$needle = needle->new($data_dir . "welcome.ref.json");
#$res    = $img1->search($needle);
#ok( defined $res, "match with different art" );

$img1   = tinycv::read($data_dir . "reclaim_space_delete_btn-20160823.test.png");
$needle = needle->new($data_dir . "reclaim_space_delete_btn-20160823.ref.json");

$res = $img1->search($needle, 0, 0);
is($res->{area}->[0]->{x}, 108, "found area is the original one");
$res = $img1->search($needle, 0, 0.9);
is($res->{area}->[0]->{x}, 108, "found area is the original one too");

$img1   = tinycv::read($data_dir . "kde.test.png");
$needle = needle->new($data_dir . "kde.ref.json");
$res    = $img1->search($needle);
ok(!defined $res, "no match with different art");

$res = undef;
try {
    $img1   = tinycv::read($data_dir . "kde.ref.png");
    $needle = needle->new($data_dir . "kde.ref.json");
    my $needle_nopng = needle->new($data_dir . "console.ref.json");
    $needle_nopng->{png} .= ".missing.png";
    $res = $img1->search([$needle_nopng, $needle]);
};
ok(defined $res, "skip needles without png");

$img1   = tinycv::read($data_dir . "console.test.png");
$needle = needle->new($data_dir . "console.ref.json");
($res, $cand) = $img1->search($needle);
ok(!defined $res, "no match different console screenshots");
# prevent tiny resolution differences to fail the test
$cand->[0]->{area}->[0]->{similarity} = sprintf "%.3f", $cand->[0]->{area}->[0]->{similarity};
is_deeply(
    $cand->[0]->{area},
    [
        {
            h          => 160,
            w          => 645,
            y          => 285,
            result     => 'fail',
            similarity => '0.946',
            x          => 190
        }
    ],
    'candidate is almost true'
);

# XXX TODO -- This need to be fixed.
# $img1   = tinycv::read($data_dir . "font-kerning.test.png");
# $needle = needle->new($data_dir . "font-kerning.ref.json");
# $res    = $img1->search($needle);
# ok( defined $res, "match when the font kerning change" );

$img1   = tinycv::read($data_dir . "instdetails.test.png");
$needle = needle->new($data_dir . "instdetails.ref.json");
$res    = $img1->search($needle);
ok(!defined $res, "no match different perform installation tabs");

# Check that if the margin is missing from JSON, is set in the hash
$img1   = tinycv::read($data_dir . "uefi.test.png");
$needle = needle->new($data_dir . "uefi.ref.json");
ok($needle->{area}->[0]->{margin} == 50, "search margin have the default value");
$res = $img1->search($needle);
ok(!defined $res, "no found a match for an small margin");

# Check that if the margin is set in JSON, is set in the hash
$img1   = tinycv::read($data_dir . "uefi.test.png");
$needle = needle->new($data_dir . "uefi-margin.ref.json");
ok($needle->{area}->[0]->{margin} == 100, "search margin have the defined value");
$res = $img1->search($needle);
ok(defined $res, "found match for a large margin");
ok($res->{area}->[0]->{x} == 378 && $res->{area}->[0]->{y} == 221, "mach area coordinates");

# This test fails in internal SLE system
$img1   = tinycv::read($data_dir . "glibc_i686.test.png");
$needle = needle->new($data_dir . "glibc_i686.ref.json");
$res    = $img1->search($needle);
ok(!defined $res, "no found a match for an small margin");
# We emulate 'assert_screen "needle", 3'
my $timeout = 3;
for (my $n = 0; $n < $timeout; $n++) {
    my $search_ratio = 1.0 - ($timeout - $n) / ($timeout);
    $res = $img1->search($needle, 0, $search_ratio);
}
ok(defined $res, "found match after timeout");

$img1   = tinycv::read($data_dir . "zypper_ref.test.png");
$needle = needle->new($data_dir . "zypper_ref.ref.json");
ok($needle->{area}->[0]->{margin} == 300, "search margin have the default value");
$res = $img1->search($needle);
ok(defined $res, "found a match for 300 margin");

needle::init($data_dir);
my @alltags = sort keys %needle::tags;

my @needles = @{needle::tags('FIXME') || []};
is(@needles, 4, "four needles found");
for my $n (@needles) {
    $n->unregister();
}

@needles = @{needle::tags('FIXME') || []};
is(@needles, 0, "no needles after unregister");

for my $n (needle::all()) {
    $n->unregister();
}

is_deeply(\%needle::tags, {}, "no tags registered");

for my $n (needle::all()) {
    $n->register();
}

is_deeply(\@alltags, [sort keys %needle::tags], "all tags restored");

$img1 = tinycv::read($data_dir . "user_settings-1.png");
my $img2 = tinycv::read($data_dir . "user_settings-2.png");
ok($img1->similarity($img2) > 53, "similarity is too small");

$img1   = tinycv::read($data_dir . "screenlock.test.png");
$needle = needle->new($data_dir . "screenlock.ref.json");
$res    = $img1->search($needle);

ok(defined $res, "match screenlock");

$img1   = tinycv::read($data_dir . "desktop-at-first-boot-kde-without-greeter-20140926.test.png");
$needle = needle->new($data_dir . "desktop-at-first-boot-kde-without-greeter-20140926.json");
$res    = $img1->search($needle);
ok(!defined $res, "KDE clearly not ready");

$img1   = tinycv::read($data_dir . "yast2_lan-hostname-tab-20140630.test.png");
$needle = needle->new($data_dir . "yast2_lan-hostname-tab-20140630.json");
$res    = $img1->search($needle);

ok(defined $res, "hostname is different");

$img1   = tinycv::read($data_dir . "desktop_mainmenu-gnomesled-sles12.test.png");
$needle = needle->new($data_dir . "desktop_mainmenu-gnomesled-sles12.json");
$res    = $img1->search($needle);

ok(!defined $res, "the mixer has a hover effect");

$img1   = tinycv::read($data_dir . "inst-video-typed-sles12b9.test.png");
$needle = needle->new($data_dir . "inst-video-typed-sles12b9.json");
$res    = $img1->search($needle);

ok(!defined $res, "the contrast is just too different");

$img1   = tinycv::read($data_dir . "xterm-started-20141204.test.png");
$needle = needle->new($data_dir . "xterm-started-20141204.json");
$res    = $img1->search($needle, 0, 0.7);

ok(defined $res, "xterm basically the same");

$img1   = tinycv::read($data_dir . "pkcon-proceed-prompt-20141205.test.png");
$needle = needle->new($data_dir . "pkcon-proceed-prompt-20141205.json");
$res    = $img1->search($needle, 0, 0.7);

ok(defined $res, "the prompt is the same to the human eye");

$img1   = tinycv::read($data_dir . "displaymanager-sle12.test.png");
$needle = needle->new($data_dir . "displaymanager-sle12.json");
$res    = $img1->search($needle);

ok(!defined $res, "the headline is completely different");

$img1   = tinycv::read($data_dir . "inst-rescuesystem-20141027.test.png");
$needle = needle->new($data_dir . "inst-rescuesystem-20141027.json");
($res, $cand) = $img1->search($needle);
is_deeply(
    $cand->[0]->{area},
    [
        {
            similarity => '0',
            x          => 245,
            w          => 312,
            result     => 'fail',
            y          => 219,
            h          => 36

        }
    ],
    'candidate total fail, but not at 0x0'
);

ok(!defined $res, "different text");

$needle = needle->new($data_dir . "ooffice-save-prompt-gnome-20160713.json");
$img1   = tinycv::read($data_dir . "ooffice-save-prompt-gnome-20160713.test.png");
($res, $cand) = $img1->search($needle);

ok(!defined $res, "font rendering changed");
is_deeply(
    $cand->[0]->{area},
    [
        {
            similarity => '0',
            x          => 273,
            w          => 483,
            result     => 'fail',
            y          => 323,
            h          => 133

        }
    ],
    'candidate total fail, but position still good'
);


$img1   = tinycv::read($data_dir . "inst-welcome-20140902.test.png");
$needle = needle->new($data_dir . "inst-welcome-20140902.json");
$res    = $img1->search($needle);

ok(defined $res, "match welcome");

$img1   = tinycv::read($data_dir . "confirmlicense-sle12.test.png");
$needle = needle->new($data_dir . "confirmlicense-sle12.json");
$res    = $img1->search($needle);

ok(defined $res, "license to confirm");

$img1   = tinycv::read($data_dir . "desktop-runner-20140523.test.png");
$needle = needle->new($data_dir . "desktop-runner-20140523.json");
$res    = $img1->search($needle);

ok(defined $res, "just some dark shade");

$img1   = tinycv::read($data_dir . "accept-ssh-host-key.test.png");
$needle = needle->new($data_dir . "accept-ssh-host-key.json");
$res    = $img1->search($needle);

ok(!defined $res, "no match for blinking cursor");

$img1   = tinycv::read($data_dir . "xorg_vt-Xorg-20140729.test.png");
$needle = needle->new($data_dir . "xorg_vt-Xorg-20140729.json");
$res    = $img1->search($needle);

ok(!defined $res, "the y goes into the line");

$needle = needle->new($data_dir . "kde-unselected-20141211.json");
$img1   = tinycv::read($data_dir . "kde-unselected-20141211.test.png");
$res    = $img1->search($needle);

ok(defined $res, "match kde is not selected");

# make sure the last area is the click area
is($res->{area}->[-1]->{w}, 17);
is($res->{area}->[-1]->{h}, 12);
is($res->{area}->[-1]->{y}, 260);
is($res->{area}->[-1]->{x}, 313);

$img1   = tinycv::read($data_dir . "other-desktop-dvd-20140904.test.png");
$needle = needle->new($data_dir . "other-desktop-dvd-20140904.json");
$res    = $img1->search($needle);

ok(!defined $res, "the hot keys don't match");

# match comparison tests
# note it's important that the workaround needle sort alphabetically
# *AFTER* the imperfect needle, so it doesn't win 'by accident'
my $perfect    = needle->new($data_dir . "login_sddm.ref.perfect.json");
my $imperfect  = needle->new($data_dir . "login_sddm.ref.imperfect.json");
my $workaround = needle->new($data_dir . "login_sddm.ref.workaround.imperfect.json");

# test that a perfect non-workaround match is preferred to imperfect
# non-workaround and workaround matches
$img1 = tinycv::read($data_dir . "login_sddm.test.png");
$res  = $img1->search([$perfect, $imperfect, $workaround], 0.9, 0);
is($res->{needle}->{name}, 'login_sddm.ref.perfect', "perfect match should win");

# test that when two equal matches fight and one is a workaround, that
# one wins
$res = $img1->search([$imperfect, $workaround], 0.9, 0);
is($res->{needle}->{name}, 'login_sddm.ref.workaround.imperfect', "workaround match should win");

# test caching via needle->get_image
needle::clean_image_cache(0);
is(needle::image_cache_size, 0, 'image cache completely cleaned');
$needle        = needle->new($data_dir . 'other-desktop-dvd-20140904.json');
$needle->{png} = $data_dir . 'other-desktop-dvd-20140904.test.png';
$img1          = $needle->get_image;
ok(defined $img1, 'image returned');
is(needle::image_cache_size, 1,     'cache size increased');
is($needle->get_image,       $img1, 'cached image returned on next call');
is(needle::image_cache_size, 1,     'cache size not further increased');
my $other_needle = needle->new($data_dir . 'xorg_vt-Xorg-20140729.json');
$other_needle->{png} = $data_dir . 'xorg_vt-Xorg-20140729.test.png';
$img2 = $other_needle->get_image;
ok($img2 != $img1, 'different image returned for other needle instance');
is(needle::image_cache_size, 2, 'cache size increased');
needle::clean_image_cache(2);
is(needle::image_cache_size, 2,     'cleaning cache to keep only 2 images should not affect cache size');
is($other_needle->get_image, $img2, 'cached image still returned');
is($needle->get_image,       $img1, 'cached image still returned');
needle::clean_image_cache(1);
ok($other_needle->get_image != $img2, 'cleaning cache to keep 1 image deleted $img2');
is($needle->get_image, $img1, 'cleaning cache to keep 1 image kept $img1');
$img2 = $other_needle->get_image;    # make $img2 the most recently used
needle::clean_image_cache(1);
is($other_needle->get_image, $img2, 'cleaning cache to keep 1 image kept $img2');
ok($needle->get_image != $img1, 'cleaning cache to keep 1 image deleted $img1');

# test needle->file is relative to default prjdir
is($needle->{file}, 'data/other-desktop-dvd-20140904.json', 'needle json path is relative to prjdir');
# test needle dir is symlinked from different location
$bmwqemu::vars{PRJDIR} = tempdir(CLEANUP => 1);
my $new_data_dir = $bmwqemu::vars{PRJDIR} . '/out-of-def-prj/test/data';
ok(make_path($bmwqemu::vars{PRJDIR} . '/out-of-def-prj/test/'), 'out of project datadir exists');
ok(symlink(abs_path($data_dir), $new_data_dir), 'needles linked');

# test needle->file is relative to different prjdir
$needle = needle->new($new_data_dir . '/login_sddm.ref.perfect.json');
ok($needle, 'needle object created from symlinked resource outside of prjdir');
is($needle->{file}, 'out-of-def-prj/test/data/login_sddm.ref.perfect.json', 'json file path is relative to prjdir');
ok(-f $needle->{png}, 'png file is accessible');

# test needle-new accepts relative path if the path is still under set prjdir
ok($needle = needle->new('out-of-def-prj/test/data/other-desktop-dvd-20140904.json'), 'needle object created with relpath');
is($needle->{file}, 'out-of-def-prj/test/data/other-desktop-dvd-20140904.json', 'needle json file path is left intact');

eval { $needle = needle->new('out-of-prj/test/data/some-needle.json') };
ok($@, 'died when accessing needle outside of prjdir');

done_testing();

# vim: set sw=4 et:

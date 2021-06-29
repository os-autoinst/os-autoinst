#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Cwd 'abs_path';
use Test::Exception;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(warning :report_warnings);
use File::Basename;
use File::Path 'make_path';
use File::Temp qw(tempdir);

BEGIN {
    $bmwqemu::vars{DISTRI}  = "unicorn";
    $bmwqemu::vars{CASEDIR} = "/var/lib/empty";
}

use needle;
use cv;

sub _cmp_similarity ($area, $expected_similarity) {
    my $similarity = delete $area->{similarity};
    my $difference = abs($similarity - $expected_similarity);
    cmp_ok $difference, '<', '0.01', 'similarity within tolerance'
      or diag explain "actual similarity: $similarity, expected similarity: $expected_similarity";
}

throws_ok(
    sub {
        needle->new('foo.json');
    },
    qr{needles not initialized}s,
    'died when constructing needle without prior call to needle::init()'
);

sub needle_init ($ret) {
    stderr_like { $ret = needle::init } qr/loaded.*needles/, 'log output for needle init';
    return $ret;
}

cv::init();
require tinycv;

my ($res, $needle, $img1, $cand);

my $data_dir         = dirname(__FILE__) . '/data/';
my $misc_needles_dir = abs_path(dirname(__FILE__)) . '/misc_needles/';

$bmwqemu::vars{NEEDLES_DIR} = $data_dir;
needle_init;

$img1   = tinycv::read($data_dir . 'bootmenu.test.png');
$needle = needle->new('bootmenu.ref.json');

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

$needle = needle->new('bootmenu-fail.ref.json');
$res    = $img1->search($needle);
ok(!defined $res, "no match");

($res, $cand) = $img1->search($needle);
ok(!defined $res,                         "no match in array context");
ok(defined $cand && ref $cand eq 'ARRAY', "candidates must be array");

$img1   = tinycv::read($data_dir . 'reclaim_space_delete_btn-20160823.test.png');
$needle = needle->new('reclaim_space_delete_btn-20160823.ref.json');

$res = $img1->search($needle, 0, 0);
is($res->{area}->[0]->{x}, 108, "found area is the original one");
$res = $img1->search($needle, 0, 0.9);
is($res->{area}->[0]->{x}, 108, "found area is the original one too");

$img1   = tinycv::read($data_dir . 'kde.test.png');
$needle = needle->new('kde.ref.json');
$res    = $img1->search($needle);
ok(!defined $res, "no match with different art");

subtest 'handle failure to load image' => sub {
    my $needle_with_png = needle->new('kde.ref.json');
    ok(my $image = $needle_with_png->get_image, 'image returned');
    my $needle_without_png  = needle->new('console.ref.json');
    my $missing_needle_path = $needle_without_png->{png} .= '.missing.png';
    stderr_like {
        is($needle_without_png->get_image, undef, 'get_image returns undef if no image present')
    } qr/Could not open image/, 'log output for missing image';

    stderr_like {
        my ($best_candidate, $candidates) = $image->search([$needle_without_png, $needle_with_png]);
        ok($best_candidate, 'has best candidate');
        is($best_candidate->{needle}, $needle_with_png, 'needle with png is best candidate')
          or diag explain $best_candidate;
        is_deeply($candidates, [], 'missing needle not even considered as candidate')
          or diag explain $candidates;
    }
    qr{.*Could not open image .*$missing_needle_path.*\n.*skipping console\.ref\: missing PNG.*},
      'needle with missing PNG skipped';
};

$img1   = tinycv::read($data_dir . 'console.test.png');
$needle = needle->new('console.ref.json');
($res, $cand) = $img1->search($needle);
ok(!defined $res, "no match different console screenshots");
subtest 'candidate is almost true' => sub {
    my $areas = $cand->[0]->{area};
    _cmp_similarity $areas->[0], 0.945;
    is_deeply $areas, [{h => 160, w => 645, x => 190, y => 285, result => 'fail'}], 'coordinates/result';
};

$img1   = tinycv::read($data_dir . 'instdetails.test.png');
$needle = needle->new('instdetails.ref.json');
$res    = $img1->search($needle);
ok(!defined $res, "no match different perform installation tabs");

# Check that if the margin is missing from JSON, is set in the hash
$img1   = tinycv::read($data_dir . 'uefi.test.png');
$needle = needle->new('uefi.ref.json');
ok($needle->{area}->[0]->{margin} == 50, "search margin have the default value");
$res = $img1->search($needle);
ok(!defined $res, "no found a match for an small margin");

# Check that if the margin is set in JSON, is set in the hash
$img1   = tinycv::read($data_dir . 'uefi.test.png');
$needle = needle->new('uefi-margin.ref.json');
ok($needle->{area}->[0]->{margin} == 100, "search margin have the defined value");
$res = $img1->search($needle);
ok(defined $res,                                                   "found match for a large margin");
ok($res->{area}->[0]->{x} == 378 && $res->{area}->[0]->{y} == 221, "mach area coordinates");

# This test fails in internal SLE system
$img1   = tinycv::read($data_dir . 'glibc_i686.test.png');
$needle = needle->new('glibc_i686.ref.json');
$res    = $img1->search($needle);
ok(!defined $res, "no found a match for an small margin");
# We emulate 'assert_screen "needle", 3'
my $timeout = 3;
for (my $n = 0; $n < $timeout; $n++) {
    my $search_ratio = 1.0 - ($timeout - $n) / ($timeout);
    $res = $img1->search($needle, 0, $search_ratio);
}
ok(defined $res, "found match after timeout");

$img1   = tinycv::read($data_dir . 'zypper_ref.test.png');
$needle = needle->new('zypper_ref.ref.json');
ok($needle->{area}->[0]->{margin} == 300, "search margin have the default value");
$res = $img1->search($needle);
ok(defined $res, "found a match for 300 margin");

needle_init;

my @alltags = sort keys %needle::tags;
my @needles = @{needle::tags('none') || []};
is(@needles, 4, "four needles found");
for my $n (@needles) {
    $n->unregister();
}

@needles = @{needle::tags('none') || []};
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

$img1   = tinycv::read($data_dir . 'screenlock.test.png');
$needle = needle->new('screenlock.ref.json');
$res    = $img1->search($needle);

ok(defined $res, "match screenlock");

$img1   = tinycv::read($data_dir . "desktop-at-first-boot-kde-without-greeter-20140926.test.png");
$needle = needle->new("desktop-at-first-boot-kde-without-greeter-20140926.json");
$res    = $img1->search($needle);
ok(!defined $res, "KDE clearly not ready");

$img1   = tinycv::read($data_dir . "yast2_lan-hostname-tab-20140630.test.png");
$needle = needle->new("yast2_lan-hostname-tab-20140630.json");
$res    = $img1->search($needle);

ok(defined $res, "hostname is different");

$img1   = tinycv::read($data_dir . "desktop_mainmenu-gnomesled-sles12.test.png");
$needle = needle->new("desktop_mainmenu-gnomesled-sles12.json");
$res    = $img1->search($needle);

ok(!defined $res, "the mixer has a hover effect");

$img1   = tinycv::read($data_dir . "inst-video-typed-sles12b9.test.png");
$needle = needle->new("inst-video-typed-sles12b9.json");
$res    = $img1->search($needle);

ok(!defined $res, "the contrast is just too different");

$img1   = tinycv::read($data_dir . "xterm-started-20141204.test.png");
$needle = needle->new("xterm-started-20141204.json");
($res, $cand) = $img1->search($needle, 0, 0.7);

ok !defined $res, 'xterm on GNOME is more blurry';
subtest 'we find the xterm though' => sub {
    my $area = $cand->[0]->{area}->[1];
    _cmp_similarity $area, 0.905881691408007;
    is_deeply $area, {x => 127, w => 39, y => 76, h => 18, result => 'fail'}, 'coordinates/result';
};

$img1   = tinycv::read($data_dir . "pkcon-proceed-prompt-20141205.test.png");
$needle = needle->new("pkcon-proceed-prompt-20141205.json");
($res, $cand) = $img1->search($needle, 0, 0.7);

ok(!defined $res, "the prompt is the same to the human eye, but it differs in shades of gray");
# the value varies between 92.9 and 92.8 dependending on used libraries
$cand->[0]->{area}->[0]->{similarity} = int($cand->[0]->{area}->[0]->{similarity} * 100 + 0.5);
is_deeply(
    $cand->[0]->{area},
    [
        {
            similarity => 93,
            x          => 17,
            w          => 237,
            result     => 'fail',
            y          => 326,
            h          => 10

        },
    ],
    'offered for needle recreation though'
);

$img1   = tinycv::read($data_dir . "displaymanager-sle12.test.png");
$needle = needle->new("displaymanager-sle12.json");
$res    = $img1->search($needle);

ok(!defined $res, "the headline is completely different");

$img1   = tinycv::read($data_dir . "inst-rescuesystem-20141027.test.png");
$needle = needle->new("inst-rescuesystem-20141027.json");
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

$needle = needle->new("ooffice-save-prompt-gnome-20160713.json");
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
$needle = needle->new("inst-welcome-20140902.json");
$res    = $img1->search($needle);

ok(defined $res, "match welcome");

$img1   = tinycv::read($data_dir . "confirmlicense-sle12.test.png");
$needle = needle->new("confirmlicense-sle12.json");
$res    = $img1->search($needle);

ok(defined $res, "license to confirm");

$img1   = tinycv::read($data_dir . "desktop-runner-20140523.test.png");
$needle = needle->new("desktop-runner-20140523.json");
$res    = $img1->search($needle);

ok(defined $res, "just some dark shade");

$img1   = tinycv::read($data_dir . "accept-ssh-host-key.test.png");
$needle = needle->new("accept-ssh-host-key.json");
$res    = $img1->search($needle);

ok(!defined $res, "no match for blinking cursor");

$img1   = tinycv::read($data_dir . "xorg_vt-Xorg-20140729.test.png");
$needle = needle->new("xorg_vt-Xorg-20140729.json");
$res    = $img1->search($needle);

ok(!defined $res, "the y goes into the line");

$needle = needle->new("kde-unselected-20141211.json");
$img1   = tinycv::read($data_dir . "kde-unselected-20141211.test.png");
$res    = $img1->search($needle);

ok(defined $res, "match kde is not selected");

# make sure the last area is the click area
is($res->{area}->[-1]->{w}, 17);
is($res->{area}->[-1]->{h}, 12);
is($res->{area}->[-1]->{y}, 260);
is($res->{area}->[-1]->{x}, 313);

$img1   = tinycv::read($data_dir . "select_patterns.test.png");
$needle = needle->new("select_patterns.json");
$res    = $img1->search($needle);

ok(!defined $res, "the green mark is unselected");

$img1   = tinycv::read($data_dir . "other-desktop-dvd-20140904.test.png");
$needle = needle->new("other-desktop-dvd-20140904.json");
$res    = $img1->search($needle);

ok(!defined $res, "the hot keys don't match");

# match comparison tests
# note it's important that the workaround needle sort alphabetically
# *AFTER* the imperfect needle, so it doesn't win 'by accident'
my $perfect    = needle->new("login_sddm.ref.perfect.json");
my $imperfect  = needle->new("login_sddm.ref.imperfect.json");
my $workaround = needle->new("login_sddm.ref.workaround.imperfect.json");

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
$needle        = needle->new('other-desktop-dvd-20140904.json');
$needle->{png} = $data_dir . 'other-desktop-dvd-20140904.test.png';
$img1          = $needle->get_image;
ok(defined $img1, 'image returned');
is(needle::image_cache_size, 1,     'cache size increased');
is($needle->get_image,       $img1, 'cached image returned on next call');
is(needle::image_cache_size, 1,     'cache size not further increased');
my $other_needle = needle->new('xorg_vt-Xorg-20140729.json');
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
is($needle->{file}, 'other-desktop-dvd-20140904.json', 'needle json path is relative to needles dir');

subtest 'needle::init accepts custom NEEDLES_DIR within working directory and otherwise falls back to "$bmwqemu::vars{PRODUCTDIR}/needles"' => sub {
    # create temporary working directory and a needle directory within it
    my $temp_working_dir = tempdir(CLEANUP => 1);
    my $needles_dir      = $bmwqemu::vars{NEEDLES_DIR} = "$temp_working_dir/some-needle-repo";
    make_path("$needles_dir/subdir");
    for my $extension (qw(json png)) {
        Mojo::File->new($misc_needles_dir, "click-point.$extension")->copy_to("$needles_dir/subdir/foo.$extension");
    }

    subtest 'custom NEEDLES_DIR used when within working directory' => sub {
        note("using working directory $temp_working_dir");
        chdir($temp_working_dir);
        $bmwqemu::vars{NEEDLES_DIR} = $needles_dir;
        is(needle_init, $needles_dir, 'custom needle dir accepted');

        ok($needle = needle->new('subdir/foo.json'), 'needle object created with needle from working directory');
        is($needle->{file}, 'subdir/foo.json',             'file path relative to needle directory');
        is($needle->{png},  "$needles_dir/subdir/foo.png", 'absolute image path assigned');
    };
};

subtest 'click point' => sub {
    needle::set_needles_dir($misc_needles_dir);

    my $needle = needle->new('click-point.json');
    is_deeply($needle->{area}->[0]->{click_point}, {xpos => 2, ypos => 4}, 'click point parsed');

    $needle = needle->new('click-point-center.json');
    is_deeply($needle->{area}->[0]->{click_point}, 'center', 'click point "center" parsed');

    like(warning {
            $needle = needle->new('click-point-multiple.json');
    }, qr/click-point-multiple\.json has more than one area with a click point/, 'warning shown');
    is_deeply($needle, undef, 'multiple click points not accepted');
};

subtest 'workaround property' => sub {
    needle::set_needles_dir($misc_needles_dir);

    my $workaround_string_needle     = needle->new('check-workaround-bsc1234567-20190522.json');
    my $workaround_hash_needle       = needle->new('check-workaround-hash-20190522.json');
    my $no_workaround_needle         = needle->new('click-point-center.json');
    my $mix_workaround_string_needle = needle->new('check-workaround-mix-bsc987321-20190617.json');
    my $mix_workaround_hash_needle   = needle->new('check-workaround-hash-mix-20190617.json');

    ok($workaround_string_needle->has_property("workaround"),     "workaround property found when it is recorded in string");
    ok($workaround_hash_needle->has_property("workaround"),       "workaround property found when it is recorded in hash");
    ok($mix_workaround_string_needle->has_property("workaround"), "workaround property found in mixed properties");
    ok($mix_workaround_hash_needle->has_property("workaround"),   "workaround property found in mixed properties");
    ok($no_workaround_needle->has_property("glossy"),             "glossy property found");
    ok(!$no_workaround_needle->has_property("workaround"),        "workaround property not found");
    ok(!$workaround_string_needle->has_property("glossy"),        "glossy property not found");
    ok(!$workaround_hash_needle->has_property("glossy"),          "glossy property not found");

    is($workaround_string_needle->get_property_value("workaround"), "bsc#1234567", "get correct value when workaround is recorded in string");
    is($workaround_hash_needle->get_property_value("workaround"), "bsc#7654321: this is a test about workaround.", "get ccorrect value when workaround is recorded in hash");
    is($mix_workaround_string_needle->get_property_value("workaround"), "bsc#987321",                                         "workaround value is correct");
    is($mix_workaround_hash_needle->get_property_value("workaround"),   "bsc#123789: This is a test for workaround property", "workaround value is correct");
    is($workaround_hash_needle->get_property_value("test"),             undef,                                                "no test value");
    is($no_workaround_needle->get_property_value("workaround"),         undef,                                                "no workaround property");
    is($no_workaround_needle->get_property_value("glossy"),             undef, "glossy property is a string, has no value");
};

subtest 'clarify error message when needles directory does not exist' => sub {
    $bmwqemu::vars{CASEDIR}     = '/tmp/foo';
    $bmwqemu::vars{PRODUCTDIR}  = '/tmp/boo/products/boo';
    $bmwqemu::vars{NEEDLES_DIR} = undef;
    throws_ok { needle::init } qr/Can't init needles from \/tmp\/boo\/products\/boo\/needles at.*/, 'do not combine CASEDIR when the default needles directory is an absolute path';

    $bmwqemu::vars{PRODUCTDIR} = 'boo/products/boo';
    throws_ok { needle::init } qr/Can't init needles from boo\/products\/boo\/needles;.*\/tmp\/foo\/boo\/products\/boo\/needles/, 'combine CASEDIR when the default needles directory is a relative path';
};

done_testing();

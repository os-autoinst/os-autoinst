#!/usr/bin/perl

use Test::Most;
use Mojo::Base -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib", "$Bin/../tools/lib";
use OpenQA::Test::Isolation qw(setup_isolated_workdir);
use OpenQA::Test::TimeLimit '5';
use Cwd 'abs_path';
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(warning :report_warnings);
use File::Basename;
use File::Path 'make_path';
use File::Temp qw(tempdir);
use Mojo::File qw(path);

my $isolation_guard = setup_isolated_workdir();

BEGIN {
    $bmwqemu::vars{DISTRI} = 'unicorn';
    $bmwqemu::vars{CASEDIR} = '/var/lib/empty';
}

use needle;
use cv;

sub _cmp_similarity ($area, $expected_similarity) {
    my $similarity = delete $area->{similarity};
    my $difference = abs $similarity - $expected_similarity;
    cmp_ok $difference, '<', '0.01', 'similarity within tolerance'
      or always_explain "actual similarity: $similarity, expected similarity: $expected_similarity";
}

sub needle_init () {
    my $ret;
    stderr_like { $ret = needle::init } qr/loaded.*needles/, 'log output for needle init';
    return $ret;
}

throws_ok(
    sub { needle->new('foo.json') },
    qr{needles not initialized}s,
    'died when constructing needle without prior call to needle::init()'
);

subtest 'needle file location and validation' => sub {
    subtest 'needle JSON file not under needle directory' => sub {
        my $misc_needles_dir = Cwd::cwd;
        needle::set_needles_dir($misc_needles_dir);
        my $invalid_json_path = 'invalid/path/to/file.json';
        throws_ok {
            needle->new($invalid_json_path);
        } qr/Needle $invalid_json_path is not under needle directory $misc_needles_dir/,
          'throws error when needle JSON file is not under needle directory';
    };

    subtest 'handle broken JSON file' => sub {
        my $sandbox = tempdir(CLEANUP => 1);
        needle::set_needles_dir($sandbox);
        my $broken_json_path = path($sandbox, 'broken.json');
        $broken_json_path->spew('{ "tags": ["test');

        like warning {
            my $needle = needle->new($broken_json_path->basename);
            is $needle, undef, 'needle object not created with broken JSON';
        }, qr/broken json.*broken\.json/, 'warning shown for broken JSON file';
    };

    subtest 'handle tags duplicates' => sub {
        my $sandbox = tempdir(CLEANUP => 1);
        needle::set_needles_dir($sandbox);
        my $tag_json_path = path($sandbox, 'tag.json');
        my $tag_png_path = path($sandbox, 'tag.png');
        $tag_png_path->spew('foobar');
        $tag_json_path->spew('{"area": [{"x" : 123, "y" : 456}],"tags": ["tag1", "tag1"]}');

        my $needle;
        combined_like { $needle = needle->new($tag_json_path->basename) } qr/\[debug\].*tag contains tag1 twice/, 'tag contains tag1 twice';
        ok $needle->has_tag('tag1'), 'tag found';
    };

    subtest 'handle invalid click point' => sub {
        my $sandbox = tempdir(CLEANUP => 1);
        needle::set_needles_dir($sandbox);
        my $invalid_click_point_json_path = path($sandbox, 'invalid-click-point.json');
        $invalid_click_point_json_path->spew('{"area": [{"click_point": "invalid"}]}');

        like warning {
            my $needle = needle->new($invalid_click_point_json_path->basename);
            is $needle, undef, 'needle object not created with invalid click point';
        }, qr/invalid-click-point\.json has an area with invalid click point/, 'warning shown for invalid click point';
    };
};

cv::init();
require tinycv;

my $data_dir = "$Bin/data/";
my $misc_needles_dir = "$Bin/misc_needles/";
$bmwqemu::vars{NEEDLES_DIR} = $data_dir;
needle_init;

subtest 'needle properties and simple search' => sub {
    my $img = tinycv::read($data_dir . 'bootmenu.test.png');
    my $needle = needle->new('bootmenu.ref.json');

    ok $needle->has_tag('inst-bootmenu'), 'tag found';
    ok !$needle->has_tag('foobar'), 'tag not found';
    ok $needle->has_property('glossy'), 'property found';
    ok !$needle->has_property('dull'), 'property not found';

    my $res = $img->search($needle);
    ok defined $res, 'match with exclude area';

    my ($res_ctx, $cand) = $img->search($needle);
    ok defined $res_ctx, 'match in array context';
    ok $res_ctx->{ok}, 'match in array context ok == 1';
    is $res_ctx->{area}->[-1]->{result}, 'ok', 'match in array context result == ok';
    ok !defined $cand, 'candidates must be undefined';

    $needle = needle->new('bootmenu-fail.ref.json');
    $res = $img->search($needle);
    ok !defined $res, 'no match';

    ($res, $cand) = $img->search($needle);
    ok !defined $res, 'no match in array context';
    ok defined $cand && ref $cand eq 'ARRAY', 'candidates must be array';
};

subtest 'search with parameters' => sub {
    my $img = tinycv::read($data_dir . 'reclaim_space_delete_btn-20160823.test.png');
    my $needle = needle->new('reclaim_space_delete_btn-20160823.ref.json');

    my $res = $img->search($needle, 0, 0);
    is $res->{area}->[0]->{x}, 108, 'found area is the original one';
    $res = $img->search($needle, 0, 0.9);
    is $res->{area}->[0]->{x}, 108, 'found area is the original one too';
};

subtest 'handle failure to load image' => sub {
    my $needle_with_png = needle->new('kde.ref.json');
    ok my $image = $needle_with_png->get_image, 'image returned';
    my $needle_without_png = needle->new('console.ref.json');
    my $missing_needle_path = $needle_without_png->{png} .= '.missing.png';
    stderr_like {
        is $needle_without_png->get_image, undef, 'get_image returns undef if no image present'
    } qr/Could not open image/, 'log output for missing image';

    stderr_like {
        my ($best_candidate, $candidates) = $image->search([$needle_without_png, $needle_with_png]);
        ok $best_candidate, 'has best candidate';
        is $best_candidate->{needle}, $needle_with_png, 'needle with png is best candidate'
          or always_explain $best_candidate;
        is_deeply $candidates, [], 'missing needle not even considered as candidate'
          or always_explain $candidates;
    }
    qr{.*Could not open image .*$missing_needle_path.*\n.*skipping console\.ref\: missing PNG.*},
      'needle with missing PNG skipped';
};

subtest 'candidate analysis' => sub {
    my $img = tinycv::read($data_dir . 'console.test.png');
    my $needle = needle->new('console.ref.json');
    my ($res, $cand) = $img->search($needle);
    ok !defined $res, 'no match different console screenshots';
    subtest 'candidate is almost true' => sub {
        my $areas = $cand->[0]->{area};
        _cmp_similarity $areas->[0], 0.945;
        is_deeply $areas, [{h => 160, w => 645, x => 190, y => 285, result => 'fail'}], 'coordinates/result';
    };
};

subtest 'margin specifications' => sub {
    my $img = tinycv::read($data_dir . 'uefi.test.png');
    subtest 'default margin from JSON' => sub {
        my $needle = needle->new('uefi.ref.json');
        is $needle->{area}->[0]->{margin}, 50, 'search margin has the default value';
        my $res = $img->search($needle);
        ok !defined $res, 'no match for small margin';
    };

    subtest 'explicit margin from JSON' => sub {
        my $needle = needle->new('uefi-margin.ref.json');
        is $needle->{area}->[0]->{margin}, 100, 'search margin has the defined value';
        my $res = $img->search($needle);
        ok defined $res, 'found match for a large margin';
        is $res->{area}->[0]->{x}, 378, 'match area x coordinates';
        is $res->{area}->[0]->{y}, 221, 'match area y coordinates';
    };
};

subtest 'search timeout emulation' => sub {
    my $img = tinycv::read($data_dir . 'glibc_i686.test.png');
    my $needle = needle->new('glibc_i686.ref.json');
    my $res = $img->search($needle);
    ok !defined $res, 'no match with strict similarity';

    my $timeout = 3;
    for (my $n = 0; $n < $timeout; $n++) {
        my $search_ratio = 1.0 - ($timeout - $n) / ($timeout);
        $res = $img->search($needle, 0, $search_ratio);
    }
    ok defined $res, 'found match after timeout';
};

subtest 'data-driven needle search cases' => sub {
    my @cases = (
        {png => 'kde.test.png', json => 'kde.ref.json', match => 0, desc => 'no match with different art'},
        {png => 'zypper_ref.test.png', json => 'zypper_ref.ref.json', match => 1, desc => 'found a match for 300 margin'},
        {png => 'screenlock.test.png', json => 'screenlock.ref.json', match => 1, desc => 'match screenlock'},
        {png => 'desktop-at-first-boot-kde-without-greeter-20140926.test.png', json => 'desktop-at-first-boot-kde-without-greeter-20140926.json', match => 0, desc => 'KDE clearly not ready'},
        {png => 'yast2_lan-hostname-tab-20140630.test.png', json => 'yast2_lan-hostname-tab-20140630.json', match => 1, desc => 'hostname is different'},
        {png => 'desktop_mainmenu-gnomesled-sles12.test.png', json => 'desktop_mainmenu-gnomesled-sles12.json', match => 0, desc => 'the mixer has a hover effect'},
        {png => 'inst-video-typed-sles12b9.test.png', json => 'inst-video-typed-sles12b9.json', match => 0, desc => 'the contrast is just too different'},
        {png => 'displaymanager-sle12.test.png', json => 'displaymanager-sle12.json', match => 0, desc => 'the headline is completely different'},
        {png => 'inst-welcome-20140902.test.png', json => 'inst-welcome-20140902.json', match => 1, desc => 'match welcome'},
        {png => 'confirmlicense-sle12.test.png', json => 'confirmlicense-sle12.json', match => 1, desc => 'license to confirm'},
        {png => 'desktop-runner-20140523.test.png', json => 'desktop-runner-20140523.json', match => 1, desc => 'just some dark shade'},
        {png => 'accept-ssh-host-key.test.png', json => 'accept-ssh-host-key.json', match => 0, desc => 'no match for blinking cursor'},
        {png => 'xorg_vt-Xorg-20140729.test.png', json => 'xorg_vt-Xorg-20140729.json', match => 0, desc => 'the y goes into the line'},
        {png => 'select_patterns.test.png', json => 'select_patterns.json', match => 0, desc => 'the green mark is unselected'},
        {png => 'other-desktop-dvd-20140904.test.png', json => 'other-desktop-dvd-20140904.json', match => 0, desc => "the hot keys don't match"},
    );

    for my $case (@cases) {
        my $img = tinycv::read($data_dir . $case->{png});
        my $needle = needle->new($case->{json});
        my $res = $img->search($needle);
        ok $case->{match} ? defined $res : !defined $res, $case->{desc};
    }
};

subtest 'special case: kde unselected' => sub {
    my $needle = needle->new('kde-unselected-20141211.json');
    my $img = tinycv::read($data_dir . 'kde-unselected-20141211.test.png');
    my $res = $img->search($needle);
    ok defined $res, 'match kde is not selected';
    is $res->{area}->[-1]->{w}, 17, 'click area width';
    is $res->{area}->[-1]->{h}, 12, 'click area height';
    is $res->{area}->[-1]->{y}, 260, 'click area y';
    is $res->{area}->[-1]->{x}, 313, 'click area x';
};

subtest 'complex candidates' => sub {
    my @complex_cases = (
        {
            png => 'xterm-started-20141204.test.png',
            json => 'xterm-started-20141204.json',
            ratio => 0.7,
            expect_area => {x => 127, w => 39, y => 76, h => 18, result => 'fail'},
            similarity => 0.9058,
            desc => 'xterm on GNOME is more blurry'
        },
        {
            png => 'inst-rescuesystem-20141027.test.png',
            json => 'inst-rescuesystem-20141027.json',
            expect_area => {x => 245, w => 312, result => 'fail', y => 219, h => 36},
            similarity => 0,
            desc => 'different text in rescue system'
        },
        {
            png => 'ooffice-save-prompt-gnome-20160713.test.png',
            json => 'ooffice-save-prompt-gnome-20160713.json',
            expect_area => {x => 273, w => 483, result => 'fail', y => 323, h => 133},
            similarity => 0,
            desc => 'font rendering changed in ooffice'
        }
    );

    for my $case (@complex_cases) {
        my $img = tinycv::read($data_dir . $case->{png});
        my $needle = needle->new($case->{json});
        my ($res, $cand) = $img->search($needle, 0, $case->{ratio} // 0);
        ok !defined $res, $case->{desc};
        my $area = $cand->[0]->{area}->[-1];
        is $area->{x}, $case->{expect_area}->{x}, "$case->{desc} candidate x";
        is $area->{y}, $case->{expect_area}->{y}, "$case->{desc} candidate y";
        _cmp_similarity $area, $case->{similarity} if defined $case->{similarity};
    }
};

subtest 'needle registration and tagging' => sub {
    needle_init;
    my @alltags = sort keys %needle::tags;
    my @needles = @{needle::tags('none') || []};
    is scalar @needles, 3, 'three needles found for tag "none"';

    for my $n (@needles) { $n->unregister() }
    is scalar @{needle::tags('none') || []}, 0, 'no needles after unregister';

    for my $n (needle::all()) { $n->unregister() }
    is_deeply \%needle::tags, {}, 'no tags registered';

    for my $n (needle::all()) { $n->register() }
    is_deeply [sort keys %needle::tags], \@alltags, 'all tags restored';

    subtest 'test tags method with multiple tags' => sub {
        my $tag1 = 'tag1';
        my $tag2 = 'tag2';
        my $tag3 = 'tag3';
        needle::set_needles_dir($misc_needles_dir);

        needle->new($_) for qw(test_tag1.json test_tag2.json test_tag3.json);
        $_->register() for needle::all();

        my $result = needle::tags($tag1);
        is scalar @$result, 2, 'two needles found for tag1';
        $result = needle::tags($tag2);
        is scalar @$result, 2, 'two needles found for tag2';
        $result = needle::tags("$tag1 $tag2");
        is scalar @$result, 1, 'one needle found with tag1 and tag2';
        $result = needle::tags("$tag2 $tag3");
        is scalar @$result, 0, 'no needle found with tag2 and tag3';
        $result = needle::tags($tag3);
        is scalar @$result, 1, 'one needle found for tag3';
        $result = needle::tags('nonexistent');
        is scalar @$result, 0, 'no needles found for nonexistent tag';

        # Restore original state
        $bmwqemu::vars{NEEDLES_DIR} = $data_dir;
        needle_init;
    };
};

subtest 'similarity and image cache' => sub {
    my $img1 = tinycv::read($data_dir . 'user_settings-1.png');
    my $img2 = tinycv::read($data_dir . 'user_settings-2.png');
    ok $img1->similarity($img2) > 53, 'similarity between user settings images';

    needle::clean_image_cache(0);
    is needle::image_cache_size, 0, 'image cache completely cleaned';

    my $needle = needle->new('other-desktop-dvd-20140904.json');
    $needle->{png} = $data_dir . 'other-desktop-dvd-20140904.test.png';
    my $cached_img = $needle->get_image;
    ok defined $cached_img, 'image returned';
    is needle::image_cache_size, 1, 'cache size increased';
    is $needle->get_image, $cached_img, 'cached image returned on next call';

    my $img_area = $needle->get_image($needle->{area}->[0]);
    ok $img_area != $cached_img, 'different image returned when get_image with area';

    my $json_hash = $needle->TO_JSON;
    is $json_hash->{name}, 'other-desktop-dvd-20140904', 'TO_JSON serialization';

    my $other_needle = needle->new('xorg_vt-Xorg-20140729.json');
    $other_needle->{png} = $data_dir . 'xorg_vt-Xorg-20140729.test.png';
    my $other_img = $other_needle->get_image;
    ok $other_img != $cached_img, 'different image returned for other needle instance';
    is needle::image_cache_size, 2, 'cache size increased to 2';

    needle::clean_image_cache(1);
    is needle::image_cache_size, 1, 'cleaning cache to keep 1 image';
    is $other_needle->get_image, $other_img, 'most recently used cached image still exists';
    ok $needle->get_image != $cached_img, 'old cached image was deleted';
};

subtest 'initialization variants' => sub {
    subtest 'default_needles_dir' => sub {
        local $bmwqemu::vars{PRODUCTDIR} = '/tmp/foo';
        is needle::default_needles_dir(), '/tmp/foo/needles', 'default needles dir correct';
    };

    subtest 'custom NEEDLES_DIR within working directory' => sub {
        my $temp_working_dir = tempdir(CLEANUP => 1);
        my $needles_dir = "$temp_working_dir/some-needle-repo";
        make_path("$needles_dir/subdir");
        for my $ext (qw(json png)) {
            path($misc_needles_dir, "click-point.$ext")->copy_to("$needles_dir/subdir/foo.$ext");
        }

        local $bmwqemu::vars{NEEDLES_DIR} = $needles_dir;
        my $orig_cwd = Cwd::cwd;
        chdir $temp_working_dir;
        is needle_init, $needles_dir, 'custom needle dir accepted';
        is needle::needles_dir(), $needles_dir, 'needles_dir returns current needle dir';
        my $needle = needle->new('subdir/foo.json');
        is $needle->{file}, 'subdir/foo.json', 'file path relative to needle directory';
        is $needle->{png}, "$needles_dir/subdir/foo.png", 'absolute image path assigned';
        chdir $orig_cwd;
    };

    subtest 'clarify error message when needles directory does not exist' => sub {
        local $bmwqemu::vars{CASEDIR} = '/tmp/foo';
        local $bmwqemu::vars{PRODUCTDIR} = '/tmp/boo/products/boo';
        local $bmwqemu::vars{NEEDLES_DIR} = undef;
        throws_ok { needle::init } qr/Can't init needles from \/tmp\/boo\/products\/boo\/needles at.*/, 'do not combine CASEDIR when the default needles directory is an absolute path';

        local $bmwqemu::vars{PRODUCTDIR} = 'boo/products/boo';
        throws_ok { needle::init } qr/Can't init needles from boo\/products\/boo\/needles;.*\/tmp\/foo\/boo\/products\/boo\/needles/, 'combine CASEDIR when the default needles directory is a relative path';
    };
};

subtest 'click point' => sub {
    needle::set_needles_dir($misc_needles_dir);

    my $click_point_1 = needle->new('click-point.json')->{area}->[0]->{click_point};
    is_deeply $click_point_1, {xpos => 2, ypos => 4}, 'click point parsed';
    my $click_point_2 = needle->new('click-point-center.json')->{area}->[0]->{click_point};
    is_deeply $click_point_2, 'center', 'click point "center" parsed';

    my $multi = needle->new('click-point-multiple-ids.json');
    is_deeply $multi->{area}->[0]->{click_point}, {xpos => 2, ypos => 4, id => 'first'}, 'first click point parsed';
    is_deeply $multi->{area}->[1]->{click_point}, {xpos => 1, ypos => 3, id => 'second'}, 'second click point parsed';

    for my $bad (qw(click-point-multiple click-point-multiple-mixed-1 click-point-multiple-mixed-2)) {
        like warning {
            my $bad_needle = needle->new("$bad.json");
            is $bad_needle, undef, "bad click point in $bad";
        }, qr/has more than one area with a click point/, "warning for $bad";
    }

    subtest 'click point copying in search' => sub {
        my $sandbox = tempdir(CLEANUP => 1);
        my $json_path = path($sandbox, 'click-point-test.json');
        $json_path->spew('{"area": [{"xpos": 0, "ypos": 0, "width": 10, "height": 10, "click_point": {"xpos": 2, "ypos": 4}}], "tags": ["test"]}');
        path($sandbox, 'click-point-test.png')->spew('dummy');

        my $orig_needles_dir = needle::needles_dir();
        needle::set_needles_dir($sandbox);
        my $needle = needle->new('click-point-test.json');
        $needle->{png} = $data_dir . 'bootmenu.test.png';

        my $img = tinycv::read($data_dir . 'bootmenu.test.png');
        my $res = $img->search($needle);
        ok defined $res, 'click-point-test needle matched';
        is_deeply $res->{area}->[0]->{click_point}, {xpos => 2, ypos => 4}, 'click point copied to search result';

        needle::set_needles_dir($orig_needles_dir);
    };
};

subtest 'workaround property' => sub {
    needle::set_needles_dir($misc_needles_dir);
    my $w_str = needle->new('check-workaround-bsc1234567-20190522.json');
    my $w_hash = needle->new('check-workaround-hash-20190522.json');
    my $no_w = needle->new('click-point-center.json');

    ok $w_str->has_property('workaround'), 'workaround property found in string';
    ok $w_hash->has_property('workaround'), 'workaround property found in hash';
    ok !$no_w->has_property('workaround'), 'no workaround property';

    is $w_str->get_property_value('workaround'), 'bsc#1234567', 'value from string';
    is $w_hash->get_property_value('workaround'), 'bsc#7654321: this is a test about workaround.', 'value from hash';
    is $w_hash->get_property_value('test'), undef, 'no test value';
    is $no_w->get_property_value('workaround'), undef, 'no workaround property';
    is $no_w->get_property_value('glossy'), undef, 'glossy property is a string, has no value';
};

subtest 'match comparison and workaround preference' => sub {
    needle::set_needles_dir($data_dir);
    my $perfect = needle->new('login_sddm.ref.perfect.json');
    my $imperfect = needle->new('login_sddm.ref.imperfect.json');
    my $workaround = needle->new('login_sddm.ref.workaround.imperfect.json');

    my $img = tinycv::read($data_dir . 'login_sddm.test.png');

    my ($res_arr, $cand_arr) = $img->search([$perfect, $imperfect, $workaround], 0.9, 0);
    is $res_arr->{needle}->{name}, 'login_sddm.ref.perfect', 'perfect match should win in array context';

    my $res_sc = $img->search([$perfect, $imperfect, $workaround], 0.9, 0);
    is $res_sc->{needle}->{name}, 'login_sddm.ref.perfect', 'perfect match should win in scalar context';

    my $res_workaround = $img->search([$imperfect, $workaround], 0.9, 0);
    is $res_workaround->{needle}->{name}, 'login_sddm.ref.workaround.imperfect', 'workaround match should win';

    my $res_tie = $img->search([$imperfect, $imperfect], 0.9, 0);
    ok defined $res_tie, 'tie breaker alphabetical names';
};

done_testing();

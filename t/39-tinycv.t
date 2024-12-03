#!/usr/bin/perl
# Checks units provided by tinycv.pm module.

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Output;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use OpenQA::Benchmark::Stopwatch;
use Test::Warnings ':report_warnings';
use File::Basename;
use needle;
use tinycv;

subtest 'overlap_lvl' => sub {
    my @test_case_list = (
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area topleft.',
            area => {xpos => 0, ypos => 0, height => 99, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area topright.',
            area => {xpos => 201, ypos => 0, height => 99, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area bottomleft.',
            area => {xpos => 0, ypos => 201, height => 99, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area bottomright.',
            area => {xpos => 201, ypos => 201, height => 99, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area left.',
            area => {xpos => 0, ypos => 100, height => 100, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area right.',
            area => {xpos => 201, ypos => 100, height => 100, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area top.',
            area => {xpos => 100, ypos => 0, height => 99, width => 100}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping area bottom.',
            area => {xpos => 100, ypos => 201, height => 99, width => 100}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping small area left.',
            area => {xpos => 0, ypos => 120, height => 60, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping small area right.',
            area => {xpos => 201, ypos => 120, height => 60, width => 99}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping small area top.',
            area => {xpos => 120, ypos => 0, height => 99, width => 60}
        },
        {
            retval => 0,
            descr => 'Check 0 for non overlapping small area bottom.',
            area => {xpos => 120, ypos => 201, height => 99, width => 60}
        },
        {
            retval => 1,
            descr => 'Check 1 for fully covering area.',
            area => {xpos => 99, ypos => 99, height => 102, width => 102}
        },
        {
            retval => 2,
            descr => 'Check 2 for area overlapping top edge.',
            area => {xpos => 90, ypos => 90, height => 20, width => 120}
        },
        {
            retval => 3,
            descr => 'Check 3 for area overlapping bottom edge.',
            area => {xpos => 90, ypos => 190, height => 20, width => 120}
        },
        {
            retval => 4,
            descr => 'Check 4 for area overlapping left edge.',
            area => {xpos => 90, ypos => 90, height => 120, width => 20}
        },
        {
            retval => 5,
            descr => 'Check 5 for area overlapping right edge.',
            area => {xpos => 190, ypos => 90, height => 120, width => 20}
        },
        {
            retval => 6,
            descr => 'Check 6 for horizontal split.',
            area => {xpos => 90, ypos => 140, height => 20, width => 120}
        },
        {
            retval => 7,
            descr => 'Check 7 for vertical split.',
            area => {xpos => 140, ypos => 90, height => 120, width => 20}
        },
        {
            retval => 8,
            descr => 'Check 8 for area overlapping top left corner.',
            area => {xpos => 90, ypos => 90, height => 20, width => 20}
        },
        {
            retval => 9,
            descr => 'Check 9 for area overlapping top right corner.',
            area => {xpos => 190, ypos => 90, height => 20, width => 20}
        },
        {
            retval => 10,
            descr => 'Check 10 for area overlapping bottom left corner.',
            area => {xpos => 90, ypos => 190, height => 20, width => 20}
        },
        {
            retval => 11,
            descr => 'Check 11 for area overlapping bottom right corner.',
            area => {xpos => 190, ypos => 190, height => 20, width => 20}
        },
        {
            retval => 12,
            descr => 'Check 12 for partial overlap through top edge.',
            area => {xpos => 140, ypos => 90, height => 20, width => 20}
        },
        {
            retval => 13,
            descr => 'Check 13 for partial overlap through bottom edge.',
            area => {xpos => 140, ypos => 190, height => 20, width => 20}
        },
        {
            retval => 14,
            descr => 'Check 14 for partial overlap through left edge.',
            area => {xpos => 90, ypos => 140, height => 20, width => 20}
        },
        {
            retval => 15,
            descr => 'Check 15 for partial overlap through right edge.',
            area => {xpos => 190, ypos => 140, height => 20, width => 20}
        }
    );
    my $area1 = {xpos => 100, ypos => 100, width => 100, height => 100};

    is(tinycv::Image::overlap_lvl($area1, $_->{area}), $_->{retval}, $_->{descr})
      for @test_case_list;
};

subtest 'search_' => sub {
    my $img =
      tinycv::read(dirname(__FILE__) . '/data' . '/bootmenu.test.png');

    stderr_like(
        sub {
            is($img->search_(undef, 0.0, 0.0),
                undef, 'Check undef for undef needle parameter');
        },
        qr/Skipping due to missing needle./,
        'Check stderr for undef needle parameter'
    );

    $bmwqemu::vars{NEEDLES_DIR} = dirname(__FILE__) . '/data/';
    needle::init;
    my $needle = needle->new('bootmenu.ref.json');

    stderr_like(
        sub {
            is($img->search_($needle, 'test', 0.0),
                undef, 'Check undef for wrong scalar for threshold param');
        },
        qr/Skipping due to illegal threshold parameter value./,
        'Check stderr for wrong scalar as threshold parameter'
    );

    stderr_like(
        sub {
            is($img->search_($needle, -0.1, 0.0),
                undef, 'Check undef for out of lower bound threshold.');
        },
        qr/Skipping due to illegal threshold parameter value./,
        'Check stderr for wrong scalar as threshold parameter'
    );

    stderr_like(
        sub {
            is($img->search_($needle, 1.1, 0.0),
                undef, 'Check undef for out of upper bound threshold.');
        },
        qr/Skipping due to illegal threshold parameter value./,
        'Check stderr for wrong scalar as threshold parameter'
    );

    stderr_like(
        sub {
            is($img->search_({4 => 8}, 0.0, 'test'),
                undef, 'Check undef for wrong scalar as search_ratio param');
        },
        qr/Skipping due to illegal search_ratio parameter value./,
        'Check stderr for wrong object as search_ratio parameter'
    );

    stderr_like(
        sub {
            is($img->search_($needle, 0.0, -0.1),
                undef, 'Check undef for out of lower bound search_ratio.');
        },
        qr/Skipping due to illegal search_ratio parameter value./,
        'Check stderr for wrong scalar as search_ratio parameter'
    );

    $needle = needle->new("bootmenu.test.img-nopng.json");
    stderr_like(
        sub {
            is($img->search_($needle, 0.0, 0.0),
                undef,
                'Check if image based needle without png returns undef.');
        },
        qr/Skipping .*: missing PNG./,
        'Check stderr for img based needle without png file.'
    );

    my $ret;
    my $levenshtein_available = eval { require Text::Levenshtein; 1 } || 0;
  SKIP: {
        skip(
            'Either the OCR program or the Text::Levenshtein module are not installed.',
            1
        ) unless (ocr::ocr_installed() && $levenshtein_available);
        $needle = needle->new('bootmenu.test.ocr-illegalrefstr.json');
        stderr_like(
            sub {
                is(
                    $img->search_($needle, 0.0, 0.0),
                    undef,
                    'Check if undef on OCR area with placeholder char in refstr.'
                );
            },
            qr/Skipping.*Illegal placeholder character .* in refstr/,
            'Check stderr for OCR needle with placeholder character in refstr.'
        );

        $needle = needle->new('bootmenu.test.ocr.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1, 'Check if OCR needle matches.');

        $needle = needle->new('bootmenu.test.ocr-fail.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 0, 'Check if OCR needle does not match wrong text.');

        $needle = needle->new('bootmenu.test.ocr-fullexclude.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if OCR needle with fully excluded area matches.');

        $needle = needle->new('bootmenu.test.ocr-excludeleft.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if OCR needle with left exclude area matches.');

        $needle = needle->new('bootmenu.test.ocr-excluderight.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if OCR needle with right exclude area matches.');

        $needle = needle->new('bootmenu.test.ocr-excludetop.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if OCR needle with top exclude area matches.');

        $needle = needle->new('bootmenu.test.ocr-excludebottom.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if OCR needle with bottom exclude area matches.');

        $needle = needle->new('bootmenu.test.ocr-excludesplithorizontal.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok(
            $ret->{ok} == 1,
            'Check if OCR needle with exclude area splitting area horizontally matches.'
        );

        $needle = needle->new('bootmenu.test.ocr-excludesplitvertical.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok(
            $ret->{ok} == 1,
            'Check if OCR needle with exclude area splitting area vertically matches.'
        );

        $needle = needle->new('bootmenu.test.ocr-excludenooverlap.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if OCR needle with non overlapping exclude area matches.');

        $needle = needle->new('bootmenu.test.ocr-multiarea.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if OCR needle with multiple OCR areas matches.');

        $needle = needle->new('bootmenu.test.img.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1, 'Check if image based needle matches.');

        $needle = needle->new('bootmenu.test.img-fail.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 0,
            'Check if wrong image based needle fails to match.');

        $needle = needle->new('bootmenu.test.img-exclude.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1,
            'Check if wrong image based needle with exclude areas matches.');

        $needle = needle->new('bootmenu.test.ocr-img-exclude.json');
        $ret = $img->search_($needle, 0.0, 0.0);
        ok($ret->{ok} == 1, 'Check if multi type area matches.');
        ok(
            ($ret->{error} <= 1) && ($ret->{error} >= 0),
            'Check error part of returned hash ref.'
        );
        ok(defined($ret->{needle}),
            'Check if needle is returned as part of hash.');
        ok(scalar(@{$ret->{area}}) == 2,
            'Check area list has correct number of matched areas.');

        my $stopwatch = OpenQA::Benchmark::Stopwatch->new()->start();
        $needle = needle->new('bootmenu.test.ocr-img-exclude.json');
        $ret = $img->search_($needle, 0.0, 0.0, $stopwatch);
        ok($ret->{ok} == 1, 'Check if run with stopwatch parameter matches.');
        stdout_like(
            sub { print($stopwatch->stop()->summary()) },
            qr/.*NAME.*TIME.*CUMULATIVE.*PERCENTAGE.*/,
            'Check stopwatch parameter.'
        );
    }

    $needle = needle->new('bootmenu.test.img-fail.json');
    $ret = $img->search_($needle, 1.0, 0.0);
    ok($ret->{ok} == 1,
        'Check if threshold parameter works setting match limit to zero.');

    $needle = needle->new('bootmenu.test.img-search_ratio.json');
    $ret = $img->search_($needle, 0.0, 0.0);
    ok($ret->{ok} == 0, 'Check if offset ROI does not match.');

    $needle = needle->new('bootmenu.test.img-search_ratio.json');
    $ret = $img->search_($needle, 0.0, 0.001);
    ok($ret->{ok} == 0,
        'Check if too low search_ratio parameter does not repair match.');

    $needle = needle->new('bootmenu.test.img-search_ratio.json');
    $ret = $img->search_($needle, 0.0, 0.003);
    ok($ret->{ok} == 1,
        'Check if sufficient search_ratio parameter repairs match.');
};

done_testing;

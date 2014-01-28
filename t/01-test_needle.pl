#!/usr/bin/perl -w -I..

use strict;
use Test::Simple tests => 12;

BEGIN {
	$ENV{DISTRI} = "unicorn";
	$ENV{CASEDIR} = "/var/lib/empty";
}

use needle;
use cv;
use Data::Dump;

my ($res, $needle, $img1, $cand);

$img1 = tinycv::read("data/bootmenu.test.png");

$needle = needle->new("data/bootmenu.ref.json");

$res = $img1->search($needle);

ok(defined $res, "match with exclude area");

($res, $cand) = $img1->search($needle);
ok(defined $res, "match in array context");
ok($res->{'ok'}, "match in array context ok == 1");
ok($res->{'area'}->[-1]->{result} eq 'ok', "match in array context result == ok");
ok(!defined $cand, "candidates must be undefined");

$needle = needle->new("data/bootmenu-fail.ref.json");
$res = $img1->search($needle);
ok(!defined $res, "no match");

($res, $cand) = $img1->search($needle);
ok(!defined $res, "no match in array context");
ok(defined $cand && ref $cand eq 'ARRAY', "candidates must be array");

$img1 = tinycv::read("data/welcome.test.png");
$needle = needle->new("data/welcome.ref.json");
$res = $img1->search($needle);
ok(defined $res, "match with different art");

$img1 = tinycv::read("data/kde.test.png");
$needle = needle->new("data/kde.ref.json");
$res = $img1->search($needle);
ok(!defined $res, "no match with different art");

$img1 = tinycv::read("data/console.test.png");
$needle = needle->new("data/console.ref.json");
$res = $img1->search($needle);
ok(!defined $res, "no match different console screenshots");

$img1 = tinycv::read("data/font-kerning.test.png");
$needle = needle->new("data/font-kerning.ref.json");
$res = $img1->search($needle);
ok(defined $res, "match when the font kerning change");

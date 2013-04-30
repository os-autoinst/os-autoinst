#!/usr/bin/perl -w -I..

use strict;
use Test::Simple tests => 3;

use needle;
use cv;

my ($res, $needle, $img1);

$img1 = tinycv::read("data/bootmenu.test.png");

$needle = needle->new("data/bootmenu.ref.json");

$res = $img1->search($needle);

ok(defined $res, "match with exclude area");

$needle = needle->new("data/bootmenu-fail.ref.json");
$res = $img1->search($needle);
ok(!defined $res, "no match");

$img1 = tinycv::read("data/welcome.test.png");
$needle = needle->new("data/welcome.ref.json");
$res = $img1->search($needle);
ok(defined $res, "match with different art");

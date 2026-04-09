#!/usr/bin/perl
#
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib", "$Bin/../tools/lib";
use OpenQA::Test::Isolation qw(setup_isolated_workdir);
use OpenQA::Test::TimeLimit '30';
use Mojo::File qw(path);

# ensure a consistent base for relative paths
chdir "$Bin/..";

my $snd2png = path($Bin, '..', 'snd2png', 'snd2png');
ok -x $snd2png, 'snd2png exists and is executable' or BAIL_OUT "snd2png not found at $snd2png, call 'make'";
my $wav = path($Bin, '..', 'snd2png', 'aplay-captured.wav');
my $original_md5_file = path($Bin, '..', 'snd2png', 'test.png.md5.original');
my ($isolation_guard, $dir) = setup_isolated_workdir();
my $test_pnm = path($dir, 'test.pnm');
ok !-e $test_pnm, 'test.pnm does not exist before';
ok qx{$snd2png $wav $test_pnm 2>&1}, 'snd2png executed with some output';
is $?, 0, 'snd2png succeeded';
ok -e $test_pnm, 'test.pnm created';
my $md5_output = qx{md5sum $test_pnm};
my ($actual_md5) = $md5_output =~ /^([0-9a-f]+)/;
my $expected_md5_content = $original_md5_file->slurp;
my ($expected_md5) = $expected_md5_content =~ /^([0-9a-f]+)/;
is $actual_md5, $expected_md5, 'md5sum matches original';

done_testing();

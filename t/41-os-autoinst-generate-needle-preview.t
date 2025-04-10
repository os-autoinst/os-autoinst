#!/usr/bin/env perl
# Copyright Roland Clobus <rclobus@rclobus.nl>
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';
use Mojo::Base -strict, -signatures;
use File::Compare qw(compare);
use Mojo::File qw(path tempdir);

use FindBin '$Bin';
use lib "$FindBin::Bin/lib", "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

sub check_os_autoinst_generate_needle_preview_default_needle ($use_stdin) {
    my $dir = tempdir("$FindBin::Script-XXXX", TMPDIR => 1, CLEANUP => 1);
    my $needle = "os-autoinst-generate-needle-preview";
    path("$Bin/data/$needle.json")->copy_to("$dir/$needle.json");
    path("$Bin/data/$needle.png")->copy_to("$dir/$needle.png");
    if ($use_stdin) {
        system("ls -1 $dir/$needle.json | $Bin/../script/os-autoinst-generate-needle-preview -");
    } else {
        system("$Bin/../script/os-autoinst-generate-needle-preview $dir/$needle.json");
    }
    is $?, 0, 'Command executed without error code';
    is compare("$dir/$needle.svg", "$Bin/data/$needle.ref.svg"), 0, 'Equal to reference';
}

check_os_autoinst_generate_needle_preview_default_needle(0);
check_os_autoinst_generate_needle_preview_default_needle(1);
is system("$Bin/../script/os-autoinst-generate-needle-preview file.does.not.exist.json"), 1 << 8, 'Basic error handling';

done_testing;

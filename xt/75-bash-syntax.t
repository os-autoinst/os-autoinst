#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);
use FindBin '$Bin';

if (!which('shfmt')) {
    plan skip_all => "shfmt not found";
}

my $res = system('tools/check-bash-scripts', 'shfmt', "$Bin/..");
is $res, 0, 'Bash script syntax is correct';

done_testing;

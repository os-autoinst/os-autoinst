#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);

if (!which('shellcheck')) {
    plan skip_all => "shellcheck not found";
}

my $res = system('tools/check-shellcheck', 'shellcheck');
is $res, 0, 'Shell style is correct';

done_testing;

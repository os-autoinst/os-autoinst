#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);

if (!which('gitlint')) {
    plan skip_all => "gitlint not found";
}

my $res = system('tools/check-git-commit-message', 'gitlint');
is $res, 0, 'git commit messages follow standards';

done_testing;

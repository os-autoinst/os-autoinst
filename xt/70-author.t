#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);
use FindBin '$Bin';

subtest 'git commit message' => sub {
    plan skip_all => "gitlint not found" unless which 'gitlint';
    is system('tools/check-git-commit-message', 'gitlint'), 0, 'git commit messages follow standards';
};

subtest 'spellcheck testapi' => sub {
    plan skip_all => "podspell or spell not found" unless which('podspell') && which('spell');
    is system(qq{sh -c "podspell $Bin/../testapi.pm | spell"}), 0, 'testapi.pm documentation has correct spelling';
};

done_testing;

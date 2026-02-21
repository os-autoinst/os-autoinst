#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);

if (!which('yamllint')) {
    plan skip_all => "yamllint not found";
}

my $res = system('tools/check-yaml-syntax', 'yamllint');
is $res, 0, 'YAML syntax is correct';

done_testing;

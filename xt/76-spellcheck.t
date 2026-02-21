#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);
use FindBin '$Bin';

if (!which('podspell') || !which('spell')) {
    plan skip_all => "podspell or spell not found";
}

my $res = system(qq{sh -c "podspell $Bin/../testapi.pm | spell"});
is $res, 0, 'testapi.pm documentation has correct spelling';

done_testing;

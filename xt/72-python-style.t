#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);

if (!which('black')) {
    plan skip_all => "black not found";
}

my $res = system('tools/check-python-style', 'black');
is $res, 0, 'Python style is correct';

done_testing;

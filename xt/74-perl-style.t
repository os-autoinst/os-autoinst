#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use File::Which qw(which);

if (!which('perlcritic')) {
    plan skip_all => "perlcritic not found";
}

my $res = system('tools/check-perl-style', 'perlcritic');
is $res, 0, 'Perl style is correct';

done_testing;

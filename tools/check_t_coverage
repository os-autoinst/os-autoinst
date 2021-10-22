#!/usr/bin/perl
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;

my $out = qx{html2text cover_db/coverage.html | grep -P '^t/\\S+\\s+[0-9]{2}\\.'};
chomp $out;
is $out, '', 'All test files have complete statement coverage';
done_testing;

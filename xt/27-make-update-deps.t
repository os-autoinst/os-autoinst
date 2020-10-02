#!/usr/bin/env perl
# Copyright (C) 2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

use strictures;
use Test::Most;
use Test::Warnings;
use FindBin '$Bin';

if (not -e "$Bin/../.git") {
    pass("Skipping all tests, not in a git repository");
    done_testing;
    exit;
}

my $build_dir = $ENV{OS_AUTOINST_BUILD_DIRECTORY} || "$Bin/..";
my $make_tool = $ENV{OS_AUTOINST_MAKE_TOOL}       || 'make';
my $make_cmd  = "$make_tool update-deps";

chdir $build_dir;
my @out = qx{$make_cmd};
my $rc  = $?;
die "Could not run $make_cmd: rc=$rc, out: @out" if $rc;

my @status = grep { not m/^\?/ } qx{git -C "$Bin/.." status --porcelain};
ok(!@status, "No changed files after '$make_cmd'") or diag @status;

done_testing;


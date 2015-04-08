#!/usr/bin/perl
# Copyright (C) 2015 SUSE Linux Products GmbH
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

use strict;
use warnings;
use Test::Compile;
use Cwd;

my $workdir;

BEGIN {
    if (getcwd =~ /\/t$/) {
        $workdir = '..';
    }
    else {
        $workdir = '.';
    }
    unshift @INC, $workdir;
}

my $test = Test::Compile->new();
$test->verbose(0);

my @files = $test->all_pm_files($workdir);
for my $file (@files) {
    #TODO: ./autoinstallstep.pm is missing installstep dependency
    next if ($file =~ /autoinstallstep.pm/);
    $test->ok($test->pm_file_compiles($file), "Compile test for $file");
}

@files = ($workdir . '/isotovideo', $test->all_pl_files($workdir));
for my $file (@files) {
    $test->ok($test->pl_file_compiles($file), "Compile test for $file");
}
$test->done_testing();

#!/usr/bin/perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
# We need :no_end_test here because otherwise it would output a no warnings
# test for each of the modules, but with the same test number
use Test::Warnings qw(:no_end_test :report_warnings);
use Test::Strict;
use File::Which;

use FindBin '$Bin';
chdir "$Bin/..";

push @Test::Strict::MODULES_ENABLING_STRICT, 'Test::Most';
push @Test::Strict::MODULES_ENABLING_WARNINGS, 'Test::Most';

$Test::Strict::TEST_SYNTAX = 1;
$Test::Strict::TEST_STRICT = 1;
$Test::Strict::TEST_WARNINGS = 1;
# We don't want to check files under external, as there might be
# missing dependencies like perltidy in OBS builds
chomp(my @external_files = qx{find external -type f});
# Skip test modules as they rely on ENABLE_MODERN_PERL_FEATURES
chomp(my @test_modules = qx{find t/data/tests t/data/wheels_dir t/data/assets t/fake/tests -name '*.pm' -not -name 'main.pm' -type f,l});
$Test::Strict::TEST_SKIP = [
    'tools/lib/perlcritic/Perl/Critic/Policy/HashKeyQuotes.pm',
    't/data/tests/main.pm',    # fails with "Can't locate testdistribution.pm" as this check does not automatically add the required lib dir
    @test_modules, @external_files
];

# Prevent any non-tracked files or files within .git (e.g. in.git/rr-cache) to
# interfer
if (-d '.git' and which('git')) {
    no warnings 'redefine';
    *Test::Strict::_all_files = sub {
        my $root = qx{git rev-parse --show-toplevel};
        chomp($root);
        $root .= '/';
        my @all_git_files = qx{git ls-files};
        chomp(@all_git_files);
        my $files_to_skip = $Test::Strict::TEST_SKIP || [];
        my %skip = map { $_ => undef } @$files_to_skip;
        return map { $root . $_ } grep { !exists $skip{$_} } @all_git_files;    # Exclude files to skip
    }
}

all_perl_files_ok('.');

#!/usr/bin/perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
# We need :no_end_test here because otherwise it would output a no warnings
# test for each of the modules, but with the same test number
use Test::Warnings qw(:no_end_test :report_warnings);
use Test::Compile;
use File::Which;

use FindBin '$Bin';
chdir "$Bin/..";

# We don't want to check files under external, as there might be
# missing dependencies like perltidy in OBS builds
chomp(my @external_files = qx{find external -type f});
# Skip test modules as they rely on ENABLE_MODERN_PERL_FEATURES
chomp(my @test_modules = qx{find t/data/tests t/data/wheels_dir t/data/assets t/fake/tests -name '*.pm' -not -name 'main.pm' -type f,l});
my $TEST_SKIP = [
    'tools/lib/perlcritic/Perl/Critic/Policy/HashKeyQuotes.pm',
    't/data/tests/main.pm',    # fails with "Can't locate testdistribution.pm" as this check does not automatically add the required lib dir
    @test_modules, @external_files
];

my $test = Test::Compile->new();
my @files;

# Prevent any non-tracked files or files within .git (e.g. in.git/rr-cache) to
# interfer
if (-d '.git' and which('git')) {
    my $root = qx{git rev-parse --show-toplevel};
    chomp($root);
    $root .= '/';
    my @all_git_files = qx{git ls-files};
    chomp(@all_git_files);
    my %skip = map { $_ => undef } @$TEST_SKIP;
    @files = map { $root . $_ } grep { !exists $skip{$_} } @all_git_files;    # Exclude files to skip
}
else {
    @files = ($test->all_pm_files('.'), $test->all_pl_files('.'));    # uncoverable statement
    my %skip = map { $_ => undef } @$TEST_SKIP;    # uncoverable statement
    @files = grep { my $f = s{^\./}{}r; !exists $skip{$f} } @files;    # uncoverable statement
}

# Only check perl files
@files = grep { /\.(?:pm|pl|t)$/ } @files;

plan tests => scalar @files;

foreach my $file (@files) {
    my $ok;
    if ($file =~ /\.pm$/) {
        $ok = $test->pm_file_compiles($file);
    }
    else {
        $ok = $test->pl_file_compiles($file);
    }
    ok($ok, "Syntax check $file");
}

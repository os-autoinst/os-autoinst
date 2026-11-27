#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib", "$Bin/../tools/lib";
use OpenQA::Test::Isolation qw(setup_isolated_workdir);
use OpenQA::Test::TimeLimit '10';
use Test::Warnings ':report_warnings';
use Cwd qw(getcwd);
use Mojo::File qw(path tempdir);

my $original_cwd = getcwd();

subtest 'default workdir is created below TMPDIR and removed on scope exit' => sub {
    my ($guard, $dir) = setup_isolated_workdir();
    ok -d $dir, 'workdir created';
    is getcwd(), "$dir", 'changed into workdir';
    path($dir, 'file')->spew('content');
    undef $guard;
    ok !-e $dir, 'workdir removed with its content on scope exit';
    is getcwd(), $original_cwd, 'original cwd restored';
};

subtest 'explicit workdir is retained on scope exit' => sub {
    my $workdir = tempdir('isolation-XXXX', TMPDIR => 1, CLEANUP => 1);
    my ($guard, $dir) = setup_isolated_workdir($workdir);
    is $dir, path($workdir)->to_abs, 'explicit workdir used';
    is getcwd(), "$dir", 'changed into explicit workdir';
    path($dir, 'marker')->spew('kept');
    undef $guard;
    is getcwd(), $original_cwd, 'original cwd restored';
    is path($workdir, 'marker')->slurp, 'kept', 'explicit workdir retained with its content';
};

subtest 'relative workdir is created relative to the original cwd' => sub {
    my $base = tempdir('isolation-XXXX', TMPDIR => 1, CLEANUP => 1);
    chdir $base;
    my ($guard, $dir) = setup_isolated_workdir('99_full_stack');
    is $dir, path($base, '99_full_stack'), 'relative workdir resolved against the original cwd';
    ok -d $dir, 'relative workdir created';
    undef $guard;
    is getcwd(), "$base", 'original cwd restored';
    chdir $original_cwd;
};

subtest 'scalar context returns only the guard' => sub {
    my $guard = setup_isolated_workdir();
    isa_ok $guard, 'Mojo::Util::_Guard', 'guard';
    isnt getcwd(), $original_cwd, 'changed into workdir';
    undef $guard;
    is getcwd(), $original_cwd, 'original cwd restored';
};

subtest 'read-only content does not keep the workdir alive' => sub {
    my ($guard, $dir) = setup_isolated_workdir();
    my $objects = path($dir, 'objects', 'e6')->make_path;
    $objects->child('object')->spew('content');
    chmod 0444, $objects->child('object');
    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, $_[0] };
        undef $guard;
    }
    is scalar @warnings, 0, 'teardown reports no warnings';
    ok !-e $dir, 'workdir with read-only content such as git objects is removed';
};

done_testing;

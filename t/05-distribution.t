#!/usr/bin/perl

# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use Test::MockModule;

subtest 'script_run' => sub {
    require distribution;
    my $d            = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(type_string => undef);
    $mock_testapi->redefine(wait_serial => undef);
    like(warning { $d->script_run }->[0],   qr/^Use of uninitialized.*\$cmd/,     'Warning on incorrect usage');
    like(warning { $d->script_run('foo') }, qr/^Use of uninitialized.*serialdev/, 'Warning on undefined serialdev');
    {
        no warnings 'once';
        $testapi::serialdev = 'my_serial';
    }
    my $typed_string = '';
    $mock_testapi->redefine(type_string => sub { $typed_string .= $_[0] });
    lives_ok { $d->script_run('foo') } 'script_run succeeds with trivial command';
    like $typed_string, qr/foo; echo .* > .*serial/, 'command is typed plus marker and redirection';
    $typed_string = '';
    like(exception { $d->script_run('foo &') }, qr/Terminator.*found.*background_script_run/, 'script_run with terminator is caught');
    lives_ok sub { $d->script_run('foo\&') },      'escaped terminator is accepted';
    lives_ok sub { $d->script_run('foo && bar') }, 'AND operator is accepted';
    lives_ok sub { $d->script_run('foo "x&"') },   'quoted & is accepted';
};

done_testing;

1;

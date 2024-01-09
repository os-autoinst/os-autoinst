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

my @wait_serial_calls;

subtest 'script_run' => sub {
    require distribution;
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(type_string => undef);
    $mock_testapi->redefine(wait_serial => undef);
    like(exception { $d->script_run }, qr/^Too few arguments/, 'Error on incorrect usage');
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
    lives_ok sub { $d->script_run('foo\&') }, 'escaped terminator is accepted';
    lives_ok sub { $d->script_run('foo && bar') }, 'AND operator is accepted';
    lives_ok sub { $d->script_run('foo "x&"') }, 'quoted & is accepted';
    $mock_testapi->redefine(wait_serial => sub {
            my $regexp = shift;
            push @wait_serial_calls, {
                regexp => $regexp,
                timeout => 90,
                expect_not_found => 0,
                quiet => undef,
                no_regex => 0,
                buffer_size => undef,
                record_output => undef,
                @_
            };
    });
    $mock_testapi->redefine(is_serial_terminal => 1);
    $d->script_run('short_command');
    # script_run calls wait_serial three times when on a serial
    # console, the call we want to check - which actually types the
    # command - is the second
    my $cmdcall = $wait_serial_calls[1];
    is $cmdcall->{buffer_size}, 141, 'appropriate buffer size used for short command';
    @wait_serial_calls = ();
    $d->script_run('long_command' x 512);
    $cmdcall = $wait_serial_calls[1];
    is $cmdcall->{buffer_size}, 6272, 'appropriate buffer size used for long command';
};

done_testing;

1;

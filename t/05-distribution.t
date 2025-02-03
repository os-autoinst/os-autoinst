#!/usr/bin/perl

# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use distribution;
use OpenQA::Test::TimeLimit '5';

my @wait_serial_calls;

subtest 'script_run' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(type_string => undef);
    $mock_testapi->redefine(wait_serial => undef);
    throws_ok { $d->script_run() } qr/^Too few arguments/, 'Error on incorrect usage';
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
    throws_ok { $d->script_run('foo &') } qr/Terminator.*found.*background_script_run/, 'script_run with terminator is caught';
    lives_ok { $d->script_run('foo\&') } 'escaped terminator is accepted';
    lives_ok { $d->script_run('foo && bar') } 'AND operator is accepted';
    lives_ok { $d->script_run('foo "x&"') } 'quoted & is accepted';
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

subtest 'set expected serial and autoinst failures' => sub {
    my $d = distribution->new;
    # Define the expected failures data
    my @failures = (
        {type => 'Soft', message => '%s Failure Message 1', pattern => 'Test Pattern1'},
        {type => 'Hard', message => '%s Failure Message 2', pattern => 'Test Pattern2'},
    );
    # Subroutine to generate failure data with formatted messages
    my sub _generate_failures ($type, %details) {
        return [
            map {
                {
                    message => sprintf($details{message}, $type),
                    pattern => qr/$details{pattern}/
                }
            } @failures
        ];
    }
    my %soft_failure = (
        message => "$failures[0]->{message}",
        pattern => "$failures[0]->{pattern}"
    );
    # Set and test Soft failures
    $d->set_expected_serial_failures(_generate_failures('Soft', %soft_failure));
    is_deeply($d->{serial_failures}, _generate_failures('Soft', %soft_failure), 'Expected Soft serial_failures matched');
    $d->set_expected_autoinst_failures(_generate_failures('Soft', %soft_failure));
    is_deeply($d->{autoinst_failures}, _generate_failures('Soft', %soft_failure), 'Expected Soft autoinst_failures matched');

    my %hard_failure = (
        message => "$failures[1]->{message}",
        pattern => "$failures[1]->{pattern}"
    );
    # Set and test Hard failures
    $d->set_expected_serial_failures(_generate_failures('Hard', %hard_failure));
    is_deeply($d->{serial_failures}, _generate_failures('Hard', %hard_failure), 'Expected Hard serial_failures matched');
    $d->set_expected_autoinst_failures(_generate_failures('Hard', %hard_failure));
    is_deeply($d->{autoinst_failures}, _generate_failures('Hard', %hard_failure), 'Expected Hard autoinst_failures matched');
};

done_testing;

1;

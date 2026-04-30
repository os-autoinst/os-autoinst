#!/usr/bin/perl

# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::Output qw(combined_like);
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
    my $wait_serial_res = 1;
    $mock_testapi->redefine(wait_serial => sub ($regexp, @args) {
            push @wait_serial_calls, {
                regexp => $regexp,
                timeout => 90,
                expect_not_found => 0,
                quiet => undef,
                no_regex => 0,
                buffer_size => undef,
                record_output => undef,
                @args
            };
            return $wait_serial_res;
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

    $wait_serial_res = 0;
    @wait_serial_calls = ();
    throws_ok { $d->script_run('foo') } qr/typing command 'foo' timed out/, 'timeout while typing command handled';

    @wait_serial_calls = ();
    combined_like { $d->script_run('foo', check_typing_cmd => 0) }
    qr/typing command 'foo' timed out/, 'timeout while typing command just logged when opted-out';
};

subtest 'pretty_serial_marker' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    my $typed_string = '';
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_testapi->redefine(type_string => sub { $typed_string .= $_[0] });
    $mock_testapi->redefine(hashed_string => sub { return 'SR' . substr $_[0], 0, 8 });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(get_var => sub { $_[0] eq 'PRETTY_SERIAL_MARKER' ? 1 : undef });
    $testapi::serialdev = 'ttyS0';

    $mock_testapi->redefine(wait_serial => sub {
            my ($regexp) = @_;
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return undef if ref($regexp) eq 'Regexp' && $regexp =~ /FC/;
            return 'SRfoo-0-';
    });

    $typed_string = '';
    $d->script_run('foo');
    like $typed_string, qr/export __OA_MARK=.*; foo\n/, 'Level 2 uses export marker';

    $mock_testapi->redefine(wait_serial => sub {
            my ($regexp) = @_;
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'FC:OK:' if ref($regexp) eq 'Regexp' && 'FC:OK:' =~ $regexp;
            return 'OA:DONE-abcd-0-foo';
    });

    $d->{_serial_marker_level} = {};
    $typed_string = '';
    is $d->script_run('foo'), 0, 'Level 3 returns exit code';
    like $typed_string, qr/foo\n$/, 'Level 3 ends with command + newline';
    is substr($typed_string, -4), "foo\n", 'Level 3 uses clean command line';

    $mock_testapi->redefine(wait_serial => sub { undef });
    $d->{_serial_marker_level} = {};
    $typed_string = '';
    is $d->_detect_serial_marker_capability(), 1, 'Fallback to Level 1 if BASH detection fails';

    $d->{_serial_marker_level}->{'test-console'} = 3;
    $mock_testapi->redefine(wait_serial => sub { undef });
    is $d->script_run('foo'), undef, 'script_run returns undef if wait_serial fails (Level 2)';

    $d->{_serial_marker_level}->{'test-console'} = 1;
    $mock_testapi->redefine(wait_serial => sub { 'SRfoo-0-' });

    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $typed_string = '';
    $d->script_run('foo');
    like $typed_string, qr/foo; echo SR.*-.*- > \/dev\/ttyS0\n/, 'Level 1 uses classic marker with redirection';

    $mock_testapi->redefine(is_serial_terminal => sub { 1 });
    $typed_string = '';
    $d->script_run('foo');
    like $typed_string, qr/foo; echo SR.*-.*-\n/, 'Level 1 uses classic marker on serial terminal';

    $mock_testapi->redefine(wait_serial => sub ($pat, %args) {
            return 0 if $pat =~ /foo; echo SR.*-\$\?-/;
            return 'SRfoo-0-';
    });
    throws_ok { $d->script_run('foo') } qr/typing command 'foo' timed out/, 'typing error handled in Level 1';
};

subtest 'serial_marker_reinstall_cached_level' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    my $typed = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });

    $d->{_serial_marker_level}->{'test-console'} = 2;
    $d->invalidate_serial_marker_hook('test-console');

    is $d->_detect_serial_marker_capability(), 2, 'Returns cached level 2';
    like $typed, qr/PROMPT_COMMAND=/, 'Calls install_serial_marker_hook (types PROMPT_COMMAND)';
    ok $d->{_serial_marker_hook_installed}->{'test-console'}, 'Hook marked as installed';
};

subtest 'reboot_safety' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    my $typed_string = '';
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_testapi->redefine(type_string => sub { $typed_string .= $_[0] });
    $mock_testapi->redefine(hashed_string => sub { return 'SR' . substr $_[0], 0, 8 });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(get_var => sub { $_[0] eq 'PRETTY_SERIAL_MARKER' ? 1 : undef });
    $testapi::serialdev = 'ttyS0';

    # Initial detection (Level 3)
    $mock_testapi->redefine(wait_serial => sub {
            my ($regexp) = @_;
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'FC:OK:' if ref($regexp) eq 'Regexp' && 'FC:OK:' =~ $regexp;
            return 'OA:DONE-abcd-0-';
    });

    $d->script_run('foo');
    like $typed_string, qr/PROMPT_COMMAND=.*OA:DONE/, 'Initial install';
    like $typed_string, qr/\.bashrc/, 'Persistence added';
    $typed_string = '';

    # Simulate console selection (e.g. after reboot/login)
    $d->console_selected('test-console');

    # Case 1: still there (e.g. persistent)
    $typed_string = '';
    $d->script_run('bar');
    unlike $typed_string, qr/PROMPT_COMMAND=.*OA:DONE/, 'No re-install if still there';
    like $typed_string, qr/bar\n/, 'Command typed';

    # Case 2: manual clear (e.g. if we know it was lost)
    $d->reset_serial_marker('test-console');
    $typed_string = '';
    $d->script_run('baz');
    like $typed_string, qr/PROMPT_COMMAND=.*OA:DONE/, 'Re-detect and re-install after resetting the serial marker';
    like $typed_string, qr/baz\n/, 'Command typed after re-installation';

    # Case 3: select_console triggers reset
    $d->{_serial_marker_hook_installed}->{'test-console'} = 1;
    $typed_string = '';
    $mock_testapi->redefine(query_isotovideo => sub { return {activated => 1} });
    $testapi::distri = $d;

    testapi::select_console('test-console');
    $d->script_run('qux');
    like $typed_string, qr/BASH:/, 'Re-detect after select_console re-activates the console';
};

subtest 'sut_marker' => sub {
    my $d = distribution->new;
    is $d->sut_marker('ls -la /tmp'), 'OA:ls -11/tmp', 'sut_marker for normal command';
    is $d->sut_marker('  ls  '), 'OA:ls2ls', 'sut_marker trims and handles short command';
    is $d->sut_marker('a'), 'OA:a1a', 'sut_marker for very short command';
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

subtest 'disable_key_repeat' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    my @called;
    $mock_testapi->redefine(enter_cmd => sub { push @called, @_ });
    $mock_testapi->noop('type_string');
    distribution->new->disable_key_repeat;
    like "@called", qr/kbdrate/, 'disable_key_repeat calls kbdrate';
};

done_testing;

1;

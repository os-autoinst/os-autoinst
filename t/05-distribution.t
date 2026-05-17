#!/usr/bin/perl

# Copyright SUSE LLC
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
    like warning { $d->script_run('foo') }, qr/^Use of uninitialized.*serialdev/, 'Warning on undefined serialdev';
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
    $mock_testapi->redefine(wait_serial => sub { 'HM' });

    is $d->_detect_serial_marker_capability(), 2, 'Returns cached level 2';
    like $typed, qr/grep -q __oa_prompt.*echo HM > \/dev\/ttyS0.*\{ echo .* \}; \. ~\/\.bashrc/s, 'Calls install_serial_marker_hook (types full setup when hook is missing)';
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
            return 'HM' if ref($regexp) eq 'Regexp' && 'HM' =~ $regexp;
            return 'OA:DONE-abcd-0-';
    });

    $d->script_run('foo');
    like $typed_string, qr/grep -q __oa_prompt.*\{ echo .* \}; \. ~\/\.bashrc/s, 'Initial install uses full setup when hook missing';
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
    like $typed_string, qr/grep -q __oa_prompt.*\{ echo .* \}; \. ~\/\.bashrc/s, 'Re-detect and re-install uses full setup when hook missing';
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
    my @test_cases = (
        {cmd => 'ls -la /tmp', expected => 'OA:ls -11/tmp', msg => 'normal command'},
        {cmd => '  ls  ', expected => 'OA:ls2ls', msg => 'trims and handles short command'},
        {cmd => 'a', expected => 'OA:a1a', msg => 'very short command'},
    );
    for my $case (@test_cases) {
        is $d->sut_marker($case->{cmd}), $case->{expected}, "sut_marker: $case->{msg}";
    }
};

subtest 'set expected serial and autoinst failures' => sub {
    my $d = distribution->new;
    my @failures = (
        {type => 'Soft', message => '%s Failure Message 1', pattern => 'Test Pattern1'},
        {type => 'Hard', message => '%s Failure Message 2', pattern => 'Test Pattern2'},
    );

    for my $f (@failures) {
        my $expected = [{message => sprintf($f->{message}, $f->{type}), pattern => qr/$f->{pattern}/}];
        $d->set_expected_serial_failures($expected);
        is_deeply $d->{serial_failures}, $expected, "set_expected_serial_failures: $f->{type}";
        $d->set_expected_autoinst_failures($expected);
        is_deeply $d->{autoinst_failures}, $expected, "set_expected_autoinst_failures: $f->{type}";
    }
};

subtest 'disable_key_repeat' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    my @called;
    $mock_testapi->redefine(enter_cmd => sub { push @called, @_ });
    $mock_testapi->noop('type_string');
    distribution->new->disable_key_repeat;
    like "@called", qr/kbdrate/, 'disable_key_repeat calls kbdrate';
};

subtest 'pretty_serial_marker_helpers' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    my %vars;
    $mock_testapi->redefine(get_var => sub { $vars{$_[0]} });
    $mock_testapi->redefine(set_var => sub { $vars{$_[0]} = $_[1] });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    my $typed = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    my $log_called = 0;
    $mock_bmwqemu->redefine(log_call => sub { $log_called++ });

    # set_pretty_serial_marker
    $d->{_serial_marker_level}->{'test-console'} = 3;
    $vars{PRETTY_SERIAL_MARKER} = 1;
    $d->set_pretty_serial_marker(1);
    is $d->get_pretty_serial_marker(), 1, 'get_pretty_serial_marker returns 1';
    is $vars{PRETTY_SERIAL_MARKER}, 1, 'PRETTY_SERIAL_MARKER var still 1';
    is $log_called, 0, 'no log_call if state matches fallback';

    $d->set_pretty_serial_marker(0);
    is $d->get_pretty_serial_marker(), 0, 'get_pretty_serial_marker returns 0 after override';
    is $vars{PRETTY_SERIAL_MARKER}, 1, 'PRETTY_SERIAL_MARKER var UNCHANGED (no pollution)';
    is $log_called, 1, 'log_call invoked when state changes';
    ok !exists $d->{_serial_marker_level}->{'test-console'}, 'marker level reset';
    $log_called = 0;

    $d->set_pretty_serial_marker(0);
    is $log_called, 0, 'no-op if value is the same';

    $typed = '';
    $d->{_pretty_serial_marker} = 1;    # Force state change for test
    $d->set_pretty_serial_marker(0);
    like $typed, qr/unset PROMPT_COMMAND/, 'unset PROMPT_COMMAND typed when turning off';

    # pretty_serial_marker_guard
    $vars{PRETTY_SERIAL_MARKER} = 1;
    $d->{_pretty_serial_marker} = undef;
    {
        my $guard = $d->pretty_serial_marker_guard(0);
        is $d->get_pretty_serial_marker(), 0, 'Value changed by guard';
        is $vars{PRETTY_SERIAL_MARKER}, 1, 'Global var remains unchanged';
    }
    is $d->get_pretty_serial_marker(), 1, 'Value restored after guard scope';
};

subtest 'serial_marker_hook_persistence' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    my $typed = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    $mock_testapi->redefine(wait_serial => sub { 'HM' });

    # First install
    $d->install_serial_marker_hook(3);
    like $typed, qr/grep -q __oa_prompt.*echo HM > \/dev\/ttyS0.*\{ echo .* \}; \. ~\/\.bashrc/s, 'Types consolidated setup with persistence when hook missing';
    ok $d->{_serial_marker_hook_persistent}->{'test-console'}, 'Persistence marked';

    # Invalidate hook but keep persistence
    $d->invalidate_serial_marker_hook('test-console');
    $typed = '';
    $mock_testapi->redefine(wait_serial => sub { 'HC' });
    $d->install_serial_marker_hook(3);
    like $typed, qr/grep -q __oa_prompt.*echo HC > \/dev\/ttyS0.*\. ~\/\.bashrc/s, 'Only types sourcing when hook is already persistent';
    unlike $typed, qr/\{ echo .* \}/, 'Does NOT re-type the full logic';
};

subtest 'serial_terminal_redirection_guard' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    my %vars = (PRETTY_SERIAL_MARKER => 1);
    $mock_testapi->redefine(get_var => sub { $vars{$_[0]} });
    $mock_testapi->redefine(set_var => sub { $vars{$_[0]} = $_[1] });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(is_serial_terminal => sub { 1 });
    $mock_testapi->redefine(backend_get_wait_still_screen_on_here_doc_input => sub { 0 });
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    my $typed = '';
    my $diag_msg = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_bmwqemu->redefine(diag => sub { $diag_msg .= $_[0] });
    $mock_bmwqemu->redefine(log_call => sub { });
    $mock_testapi->redefine(wait_serial => sub {
            my ($regexp) = @_;
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'FC:OK:' if ref($regexp) eq 'Regexp' && 'FC:OK:' =~ $regexp;
            return 'OA:DONE-abcd-0-';
    });

    my @cases = (
        {cmd => 'foo', guard => 0, msg => 'normal command without serial redirection does not trigger the guard'},
        {cmd => 'foo | tee /dev/ttyS0', guard => 1, msg => 'piping to the serial terminal triggers the guard'},
        {cmd => 'bar > /dev/ttyS0', guard => 1, msg => 'redirection to the serial terminal triggers the guard'},
        {cmd => 'baz >> /dev/ttyS0', guard => 1, msg => 'appending to the serial terminal triggers the guard'},
    );

    for my $case (@cases) {
        $typed = '';
        $diag_msg = '';
        $vars{PRETTY_SERIAL_MARKER} = 1;
        $d->{_serial_marker_level}->{'test-console'} = 3;
        $testapi::serialdev = 'ttyS0';
        $d->{serial_term_prompt} = '# ';

        $d->script_run($case->{cmd});
        if ($case->{guard}) {
            like $typed, qr/OA_NO_MARKER=1; /, $case->{msg};
            like $diag_msg, qr/Manual redirection to \/dev\/ttyS0 is deprecated/, 'deprecation warning shown';
        }
        else {
            unlike $typed, qr/OA_NO_MARKER=1; /, $case->{msg};
            unlike $diag_msg, qr/Manual redirection to \/dev\/ttyS0 is deprecated/, 'no deprecation warning for normal command';
        }
        is $vars{PRETTY_SERIAL_MARKER}, 1, "PRETTY_SERIAL_MARKER is active again after '$case->{cmd}'";
    }

    $typed = '';
    delete $d->{_serial_marker_hook_installed}->{'test-console'};
    delete $d->{_serial_marker_hook_persistent}->{'test-console'};
    $d->{_serial_marker_level}->{'test-console'} = 3;
    $d->install_serial_marker_hook(3);
    like $typed, qr/__oa_prompt\(\) \{ r=\$\?; if \[ -n "\$OA_NO_MARKER" \]/, '__oa_prompt must capture the exit status r=$? as the absolute first statement to prevent internal conditional checks from overwriting it';
};
done_testing;

1;

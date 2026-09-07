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
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    $mock_testapi->redefine(type_string => undef);
    $mock_testapi->redefine(wait_serial => undef);
    throws_ok { $d->script_run() } qr/^Too few arguments/, 'Error on incorrect usage';
    my @warns = warnings { $d->script_run('foo') };
    like $warns[0], qr/^Use of uninitialized.*serialdev/, 'Warning on undefined serialdev';
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
    my $oanm_len = length '_OANM=1; ';
    $d->script_run('short_command');
    # First script_run also detects marker capability, which types an extra
    # 'unset PROMPT_COMMAND' and waits for the prompt, so the call that types
    # the command is the third
    my $cmdcall = $wait_serial_calls[2];
    is $cmdcall->{buffer_size}, 141 + $oanm_len, 'appropriate buffer size used for short command (base + _OANM prefix)';
    # marker capability is now cached, so no 'unset PROMPT_COMMAND' wait
    # precedes this call: the command is at index 1
    @wait_serial_calls = ();
    $d->script_run('long_command' x 512);
    $cmdcall = $wait_serial_calls[1];
    is $cmdcall->{buffer_size}, 6272 + $oanm_len, 'appropriate buffer size used for long command (base + _OANM prefix)';

    $wait_serial_res = 0;
    @wait_serial_calls = ();
    throws_ok { $d->script_run('foo') } qr/typing command '_OANM=1; foo' timed out/, 'timeout while typing command handled';

    @wait_serial_calls = ();
    combined_like { $d->script_run('foo', check_typing_cmd => 0) }
    qr/typing command '_OANM=1; foo' timed out/, 'timeout while typing command just logged when opted-out';
};

subtest 'pretty_serial_marker' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    $mock_bmwqemu->noop('diag');
    my $typed_string = '';
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_testapi->redefine(type_string => sub { $typed_string .= $_[0] });
    $mock_testapi->redefine(hashed_string => sub { return 'SR' . substr $_[0], 0, 8 });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(get_var => sub { $_[0] eq 'PRETTY_SERIAL_MARKER' ? (defined $_[1] ? $_[1] : 1) : undef });
    $testapi::serialdev = 'ttyS0';

    $mock_testapi->redefine(wait_serial => sub ($regexp, @) {
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return undef if ref($regexp) eq 'Regexp' && $regexp =~ /FC/;
            return 'SRfoo-0-';
    });

    $typed_string = '';
    $d->{_serial_marker_level}->{'test-console'} = 2;
    $d->script_run('foo');
    like $typed_string, qr/export _OAM=.*; foo\n/, 'Level 2 uses export marker';

    $mock_testapi->redefine(wait_serial => sub ($regexp, @) {
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'FC:OK:' if ref($regexp) eq 'Regexp' && 'FC:OK:' =~ $regexp;
            return 'OA:DONE-abcd-0-OA:foo3foo';
    });

    $d->{_serial_marker_level} = {};
    $typed_string = '';
    is $d->script_run('foo'), 0, 'Level 3 returns exit code';
    like $typed_string, qr/foo\n$/, 'Level 3 ends with command + newline';
    is substr($typed_string, -4), "foo\n", 'Level 3 uses clean command line';

    $mock_testapi->redefine(wait_serial => sub { undef });
    $d->{_serial_marker_level} = {};
    $typed_string = '';
    is $d->detect_serial_marker_capability(), 1, 'Fallback to Level 1 if BASH detection fails';

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
    like $typed_string, qr/_OANM=1; foo; echo SR.*-.*-\n/, 'Level 1 uses classic marker on serial terminal';

    $mock_testapi->redefine(wait_serial => sub ($pat, %) {
            return 0 if $pat =~ /foo; echo SR.*-\$\?-/;
            return 'SRfoo-0-';
    });
    throws_ok { $d->script_run('foo') } qr/typing command '_OANM=1; foo' timed out/, 'typing error handled in Level 1';
};

subtest 'serial_marker_reinstall_cached_level' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    my $typed = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });

    $d->{_serial_marker_level}->{'test-console'} = 2;
    $d->invalidate_serial_marker_hook('test-console');

    is $d->detect_serial_marker_capability(), 2, 'Returns cached level 2';
    like $typed, qr/grep -q '_OAPV=\d+'.*\. ~\/\.bashrc/, 'Calls install_serial_marker_hook (types consolidated setup with sourcing)';
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
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(get_var => sub { $_[0] eq 'PRETTY_SERIAL_MARKER' ? (defined $_[1] ? $_[1] : 1) : undef });
    $testapi::serialdev = 'ttyS0';

    # Initial detection (Level 3)
    $mock_testapi->redefine(wait_serial => sub ($regexp, @) {
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'FC:OK:' if ref($regexp) eq 'Regexp' && 'FC:OK:' =~ $regexp;
            my $regexp_str = "$regexp";
            my ($fp) = grep { (my $c = $regexp_str) =~ s/\\//g; $c =~ /\Q$_\E/ }
              map { $d->sut_marker($_) } qw(foo bar baz qux);
            return "OA:DONE-abcd-0-$fp";
    });

    $d->script_run('foo');
    like $typed_string, qr/grep -q '_OAPV=\d+'.*_oap\(\).*OA:DONE.*\. ~\/\.bashrc/s, 'Initial install';
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
    like $typed_string, qr/grep -q '_OAPV=\d+'.*_oap\(\).*OA:DONE.*\. ~\/\.bashrc/s, 'Re-detect and re-install after resetting the serial marker';
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

subtest 'level3_marker_correlation' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    $testapi::serialdev = 'ttyS0';

    my $typed = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    $d->install_serial_marker_hook(3);
    like $typed, qr'c=\$\(HISTTIMEFORMAT= history 1\);c=\$\{c#\*\[0-9\]  \}',
      'level-3 shell hook captures the just-run command via in-memory history (no fc off-by-one)';
    like $typed, qr'l=\$\{#c\};t=\$c;\[ \$l -ge 4 \]&&t=\$\{c: -4\};printf.*OA:DONE',
      'level-3 shell hook emits the compact head4+len+tail4 command fingerprinting script';
    unlike $typed, qr'fc -ln -1',
      'level-3 shell hook no longer uses fc -ln -1 (off-by-one lag emitting the previous command marker one prompt late)';

    $d->{_serial_marker_level}->{'test-console'} = 3;
    $d->{_serial_marker_hook_installed}->{'test-console'} = 1;
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(query_isotovideo => sub { });

    my @regexes_seen;
    $mock_testapi->redefine(wait_serial => sub ($regexp, @) {
            push @regexes_seen, $regexp;
            return 'OA:DONE-1234-0-OA:curl11logs';
    });

    my $exit_code = $d->script_run('curl --logs');
    is $exit_code, 0, 'Level 3 script_run returns correct exit code on successful command match';
    is scalar(@regexes_seen), 1, 'Only wait_serial for the anchored fingerprint is called when match succeeds';
    like $regexes_seen[0], qr/OA:DONE-\[0-9a-f\]\{4\}-\(\\d\+\)-OA(?:\\:|:)curl11logs/,
      'wait_serial matches the exact head4+len+tail4 command fingerprint of curl --logs';

    my $fp = $d->sut_marker('curl --logs');
    my $regex = qr/OA:DONE-[0-9a-f]{4}-(\d+)-\Q$fp\E/;
    my $stale_systemctl = "OA:DONE-aaaa-1-OA:syst15_ctl\n";
    my $stale_tar = "OA:DONE-bbbb-2-OA:tar_7_tar\n";
    my $correct_curl = "OA:DONE-cccc-0-OA:curl11logs\n";

    unlike $stale_systemctl, $regex, 'Stale unconsumed systemctl markers from other commands are ignored by the curl regex';
    unlike $stale_tar, $regex, 'Stale unconsumed tar markers from other commands are ignored by the curl regex';
    like $correct_curl, $regex, 'The target curl marker matches the anchored regex perfectly';

    my ($extracted_exit) = ($correct_curl =~ $regex);
    is $extracted_exit, 0, 'Exit code is correctly extracted from the fingerprinted marker';

    @regexes_seen = ();
    $mock_testapi->redefine(wait_serial => sub ($regexp, @) { push @regexes_seen, $regexp; return undef });
    $exit_code = $d->script_run('curl --logs');
    is $exit_code, undef, 'Anchored match miss fails closed with undef instead of an unreliable generic fallback';
    is scalar(@regexes_seen), 1, 'No second generic wait_serial is issued, preventing stale-marker mismatch and doubled timeout';
    like $regexes_seen[0], qr/OA:DONE-\[0-9a-f\]\{4\}-\(\\d\+\)-OA(?:\\:|:)curl11logs/, 'The single wait_serial call uses the anchored fingerprint';
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

    # First install
    $d->install_serial_marker_hook(3);
    like $typed, qr/grep -q '_OAPV=\d+'.*\. ~\/\.bashrc/, 'Types consolidated setup with persistence and sourcing';
    ok $d->{_serial_marker_hook_persistent}->{'test-console'}, 'Persistence marked';

    # Invalidate hook but keep persistence
    $d->invalidate_serial_marker_hook('test-console');
    $typed = '';
    $d->install_serial_marker_hook(3);
    like $typed, qr/\. ~\/\.bashrc/, 'Types setup again (with sourcing) when invalidated';
};

subtest 'serial_marker_hook_version_migration' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    my $typed = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    $d->install_serial_marker_hook(3);
    like $typed, qr/grep -q '_OAPV=\d+'/, 'Guard keys on a version tag, not mere _oap presence';
    like $typed, qr/sed -i '[^']*_oap[^']*' ~\/\.bashrc ~\/\.profile/,
      'Stale hook lines are stripped before reinstall so an old-format _oap persisted by a previous os-autoinst is replaced';
    like $typed, qr/echo '_OAPV=\d+;_oap\(\)/, 'The version tag is persisted together with the hook definition';
};

subtest 'serial markers are skipped for manual redirections and multiline commands' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    my %vars = (PRETTY_SERIAL_MARKER => 1);
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(is_serial_terminal => sub { 1 });
    my $typed = '';
    my $diag_msg = '';
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_bmwqemu->redefine(diag => sub { $diag_msg .= $_[0] });
    $mock_bmwqemu->redefine(log_call => sub { });
    $mock_testapi->redefine(wait_serial => sub ($regexp, @) {
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'FC:OK:' if ref($regexp) eq 'Regexp' && 'FC:OK:' =~ $regexp;
            return 'OA:DONE-abcd-0-';
    });

    my @cases = (
        {cmd => 'foo', guard => 0, msg => 'normal command without serial redirection does not trigger the guard'},
        {cmd => "foo\n", guard => 0, msg => 'trailing newline characters does not trigger the guard'},
        {cmd => "foo\nbar\n", guard => 2, msg => 'newline characters trigger the guard'},
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
        if ($case->{guard} == 1) {
            like $typed, qr/_OANM=1; /, $case->{msg};
            like $diag_msg, qr/Manual redirection to \/dev\/ttyS0 is deprecated/, 'deprecation warning shown';
        }
        elsif ($case->{guard} == 2) {
            like $typed, qr/_OANM=1; /, $case->{msg};
            like $diag_msg, qr/Temporarily disabling.*newline characters/, 'info message shown';
        }
        else {
            unlike $typed, qr/_OANM=1; /, $case->{msg};
            unlike $diag_msg, qr/Manual redirection to \/dev\/ttyS0 is deprecated/, 'no deprecation warning for normal command';
            unlike $diag_msg, qr/Temporarily disabling.*newline characters/, 'no newline info shown';
        }
        is $vars{PRETTY_SERIAL_MARKER}, 1, "PRETTY_SERIAL_MARKER is active again after '$case->{cmd}'";
    }

    $typed = '';
    delete $d->{_serial_marker_hook_installed}->{'test-console'};
    delete $d->{_serial_marker_hook_persistent}->{'test-console'};
    $d->{_serial_marker_level}->{'test-console'} = 3;
    $d->install_serial_marker_hook(3);
    like $typed, qr/_oap\(\)\{ r=\$\?;if \[ -n "\$_OANM" \]/, '_oap must capture the exit status r=$? as the absolute first statement to prevent internal conditional checks from overwriting it';
};

subtest 'terminal_session_boundary' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    my $typed = '';
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $mock_testapi->redefine(current_console => sub { 'x11' });
    $mock_testapi->redefine(get_var => sub { $_[0] eq 'PRETTY_SERIAL_MARKER' ? (defined $_[1] ? $_[1] : 1) : undef });
    $testapi::serialdev = 'ttyS0';

    $mock_testapi->redefine(wait_serial => sub ($regexp, @) {
            return 'BASH:4.4:' if ref($regexp) eq 'Regexp' && 'BASH:4.4:' =~ $regexp;
            return 'OA:DONE-abcd-0-';
    });

    $d->script_run('first_cmd');
    like $typed, qr/_oap/, 'pretty serial marker hook is initially configured and installed on the terminal session';

    $typed = '';
    $d->script_run('second_cmd');
    unlike $typed, qr/_oap/, 'hook re-installation is skipped on subsequent commands if cached status is stale';

    $d->invalidate_serial_marker_hook('x11');
    $typed = '';
    $d->script_run('third_cmd');
    like $typed, qr/_oap/, 'hook is successfully re-installed on the next command after cached status is explicitly invalidated';
};

subtest 'become_user' => sub {
    my $d = distribution->new;
    my $mock_testapi = Test::MockModule->new('testapi');
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    my $typed = '';
    $mock_testapi->redefine(query_isotovideo => sub { });
    $mock_testapi->redefine(type_string => sub { $typed .= $_[0] });
    $mock_testapi->redefine(is_serial_terminal => sub { 0 });
    $mock_testapi->redefine(current_console => sub { 'test-console' });
    $mock_testapi->redefine(get_var => sub { $_[0] eq 'PRETTY_SERIAL_MARKER' ? 1 : undef });
    $testapi::serialdev = 'ttyS0';
    $mock_testapi->redefine(wait_serial => undef);
    $d->{_serial_marker_level}->{'test-console'} = 3;
    $d->become_user('geeko');
    like $typed, qr/su - geeko/, 'become_user types su command to switch session user';
    like $typed, qr/_oap/, 'become_user automatically reinstalls the shell synchronization hook after invalidation';
    throws_ok { $d->become_user('geeko; rm -rf /') } qr/Invalid username/, 'invalid username is rejected';
};

done_testing;

1;

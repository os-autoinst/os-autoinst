#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::Mock::Time;
use File::Temp;
use Test::Output qw(combined_like stderr_like);
use Test::Fatal;
use Test::Warnings qw(:all :report_warnings);
use Scalar::Util 'looks_like_number';

use OpenQA::Isotovideo::Interface;
use consoles::console;

require bmwqemu;

ok(looks_like_number($OpenQA::Isotovideo::Interface::version), 'isotovideo version set (variable is considered part of test API)');

my $cmds;
use Test::MockModule;
my $mod       = Test::MockModule->new('myjsonrpc');
my $fake_exit = 0;

# define variables for 'fake_read_json'
my $report_timeout_called         = 0;
my $fake_pause_on_timeout         = 0;
my $fake_needle_found             = 1;
my $fake_needle_found_after_pause = 0;

# define 'write_with_thumbnail' to fake image
sub write_with_thumbnail { }

sub fake_send_json ($to_fd, $cmd) {
    push(@$cmds, $cmd);
}

sub fake_read_json ($fd) {
    my $lcmd = $cmds->[-1];
    my $cmd  = $lcmd->{cmd};
    if ($cmd eq 'backend_wait_serial') {
        my $str = $lcmd->{regexp};
        $str =~ s,\\d\+(\\s\+\\S\+)?,$fake_exit,;
        return {ret => {matched => 1, string => $str}};
    }
    elsif ($cmd eq 'backend_select_console') {
        return {ret => {activated => 0}};
    }
    elsif ($cmd eq 'report_timeout') {
        $report_timeout_called += 1;
        return {ret => 0} unless ($fake_pause_on_timeout);

        $fake_pause_on_timeout = 0;    # only fake the pause once to prevent enless loop
        return {ret => 1};
    }
    elsif ($cmd eq 'backend_is_serial_terminal') {
        return {ret => {yesorno => 0}};
    }
    elsif ($cmd eq 'check_screen') {
        if ($fake_needle_found || ($fake_needle_found_after_pause && !$fake_pause_on_timeout)) {
            return {ret => {found => {needle => 1}}};
        }
        return {
            ret => {
                timeout        => 1,
                tags           => [qw(fake tags)],
                failed_screens => [{
                        image => 'fake image',
                        frame => 42,
                }],
            }
        };
    }
    elsif ($cmd eq 'backend_mouse_hide') {
        return {ret => 1};
    }
    elsif ($cmd eq 'backend_get_last_mouse_set') {
        return {ret => {x => 100, y => 100}};
    }
    elsif ($cmd eq 'backend_mouse_set') {
        return {ret => {x => 100, y => 100}};
    }
    else {
        note "mock method not implemented \$cmd: $cmd\n";
    }
    return {};
}

$mod->redefine(send_json => \&fake_send_json);
$mod->redefine(read_json => \&fake_read_json);

use testapi qw(is_serial_terminal :DEFAULT);
use basetest;
my $mock_basetest = Test::MockModule->new('basetest');
$mock_basetest->redefine(_result_add_screenshot => sub { my ($self, $result) = @_; });
$autotest::current_test = basetest->new();

# we have to mock out wait_screen_change for the type_string tests
# that use it, as it doesn't work with the fake send_json and read_json
my $mod2 = Test::MockModule->new('testapi');

my $mock_bmwqemu = Test::MockModule->new('bmwqemu');

subtest 'type_string' => sub {
    ## no critic (ProhibitSubroutinePrototypes)
    sub fake_wait_screen_change(&@) {
        my ($callback, $timeout) = @_;
        $callback->() if $callback;
    }

    $mod2->redefine(wait_screen_change => \&fake_wait_screen_change);

    stderr_like { type_string 'hallo' } qr/<<< testapi::type_string/, 'type_string log output';
    is_deeply $cmds, [{cmd => 'backend_type_string', max_interval => 250, text => 'hallo'}], 'type_string called';
    $cmds = [];

    stderr_like { type_string 'hallo', 4 } qr/<<< testapi::type_string.*interval=4/, 'type_string log output';
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 4, text => 'hallo'}]);
    $cmds = [];

    # after we tested the log output in some calls we can switch it off for the
    # rest to reduce the noise
    $mock_bmwqemu->noop('log_call', 'diag', 'fctres');

    type_string 'hallo', secret => 1;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 250, text => 'hallo'}]);
    $cmds = [];

    type_string 'hallo', secret => 1, max_interval => 10;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 10, text => 'hallo'}]);
    $cmds = [];

    type_string 'hallo', wait_screen_change => 3;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 250, text => 'hal'}, {cmd => 'backend_type_string', max_interval => 250, text => 'lo'},]);
    $cmds = [];

    type_string 'hallo', wait_screen_change => 2;
    is_deeply(
        $cmds,
        [
            {cmd => 'backend_type_string', max_interval => 250, text => 'ha'},
            {cmd => 'backend_type_string', max_interval => 250, text => 'll'},
            {cmd => 'backend_type_string', max_interval => 250, text => 'o'},
        ]);
    $cmds = [];

    type_string 'hallo', wait_screen_change => 3, max_interval => 10;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 10, text => 'hal'}, {cmd => 'backend_type_string', max_interval => 10, text => 'lo'},]);
    $cmds = [];

    type_string 'true', lf => 1;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 250, text => "true\n"}]);
    $cmds = [];

    $testapi::password = 'stupid';
    type_password;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 100, text => 'stupid'}]);
    $cmds = [];

    type_password 'hallo';
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 100, text => 'hallo'}]);
    $cmds = [];

    type_password 'hallo', max_interval => 5;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 5, text => 'hallo'}]);
    $cmds = [];
};

subtest 'enter_cmd' => sub {
    enter_cmd 'true';
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 250, text => "true\n"}]);
    $cmds = [];
};

subtest 'eject_cd' => sub {
    eject_cd;
    eject_cd device => 'foo';
    is_deeply $cmds, [{cmd => 'backend_eject_cd'}, {cmd => 'backend_eject_cd', device => 'foo'}];
    $cmds = [];
};

subtest 'type_string with wait_still_screen' => sub {
    my $wait_still_screen_called = 0;
    my $module                   = Test::MockModule->new('testapi');
    $module->redefine(wait_still_screen => sub { $wait_still_screen_called = 1; });
    type_string 'hallo', wait_still_screen => 1;
    is_deeply($cmds, [{cmd => 'backend_type_string', text => 'hallo', max_interval => 250}]);
    $cmds = [];
    ok($wait_still_screen_called, 'wait still screen should have been called');
    type_string 'test2_adding_timeout', wait_still_screen => 1, timeout => 5, max_interval => 100;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 100, text => 'test2_adding_timeout'}]);
    $cmds = [];
    ok($wait_still_screen_called, 'wait still screen should have been called');
    type_string 'test3_with_sim_level', wait_still_screen => 1, timeout => 5, similarity_level => 38, max_interval => 100;
    is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 100, text => 'test3_with_sim_level'}]);
    $cmds = [];
    ok($wait_still_screen_called, 'wait still screen should have been called');
};


$testapi::password = 'stupid';
type_password;
is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 100, text => 'stupid'}]);
$cmds = [];

send_key 'ret';
is_deeply($cmds, [{cmd => 'backend_send_key', key => 'ret'}], 'send_key with no default arguments') || diag explain $cmds;
$cmds = [];

$mock_bmwqemu->redefine(result_dir => File::Temp->newdir());

subtest 'send_key with wait_screen_change' => sub {
    my $mock_testapi              = Test::MockModule->new('testapi');
    my $wait_screen_change_called = 0;
    $mock_testapi->redefine(wait_screen_change => sub(&@) { shift->(); $wait_screen_change_called = 1 });
    send_key 'ret', wait_screen_change => 1;
    is(scalar @$cmds, 1, 'send_key waits for screen change') || diag explain $cmds;
    $cmds = [];
    ok($wait_screen_change_called, 'wait_screen_change called by send_key');
};

is($autotest::current_test->{dents}, 0, 'no soft failures so far');
$mock_bmwqemu->unmock('log_call');
stderr_like(\&record_soft_failure, qr/record_soft_failure\(reason=undef\)/, 'soft failure recorded in log');
is($autotest::current_test->{dents},             1, 'one dent recorded');
is(scalar @{$autotest::current_test->{details}}, 1, 'exactly one detail added recorded');

stderr_like { record_soft_failure('workaround for bug#1234') } qr/record_soft_failure.*reason=.*workaround for bug#1234.*/, 'soft failure with reason';
is($autotest::current_test->{dents},             2, 'one more dent recorded');
is(scalar @{$autotest::current_test->{details}}, 2, 'exactly one more detail added recorded');
my $details    = $autotest::current_test->{details}[-1];
my $details_ok = is($details->{title}, 'Soft Failed', 'title for soft failure added');
$details_ok &= is($details->{result}, 'softfail', 'result correct');
$details_ok &= like($details->{text}, qr/basetest-[0-9]+.*txt/, 'file for soft failure added');
diag explain $details unless $details_ok;
$mock_bmwqemu->noop('log_call');

require distribution;
testapi::set_distribution(distribution->new());
select_console('a-console');
is(is_serial_terminal, 0,           'Not a serial terminal');
is(current_console,    'a-console', 'Current console is the a-console');

subtest 'script_run' => sub {
    # just save ourselves some time during testing
    $mock_bmwqemu->redefine(wait_for_one_more_screenshot => sub { sleep 0; });

    $testapi::serialdev = 'null';

    $mock_bmwqemu->unmock('fctres');
    stderr_like { is(assert_script_run('true'), undef, 'nothing happens on success') } qr/wait_serial/, 'log';
    $mock_bmwqemu->noop('fctres');
    $fake_exit = 1;
    like(exception { assert_script_run 'false', 42; }, qr/command.*false.*failed at/, 'with timeout option (deprecated mode)');
    like(exception { assert_script_run 'false', 0; },  qr/command.*false.*timed out/, 'exception message distinguishes failed/timed out');
    like(
        exception { assert_script_run 'false', 7, 'my custom fail message'; },
        qr/command.*false.*failed: my custom fail message at/,
        'custom message on die (deprecated mode)'
    );
    like(
        exception { assert_script_run('false', fail_message => 'my custom fail message'); },
        qr/command.*false.*failed: my custom fail message at/,
        'using named arguments'
    );
    like(
        exception { assert_script_run('false', timeout => 0, fail_message => 'my custom fail message'); },
        qr/command.*false.*timed out/,
        'using two named arguments; fail message does not apply on timeout'
    );
    $fake_exit = 0;
    $cmds      = [];
    is(script_run('true'), '0', 'script_run with no check of success, returns exit code');
    like($cmds->[1]->{text}, qr/; echo /);
    $cmds = [];
    is(script_run('true', output => 'foo'), '0', 'script_run with no check of success and output, returns exit code');
    like($cmds->[1]->{text}, qr/; echo .*Comment: foo/);
    $fake_exit = 1;
    is(script_run('false'), '1', 'script_run with no check of success, returns exit code');
    is(script_run('false', output => 'foo'), '1',   'script_run with no check of success and output, returns exit code');
    is(script_run('false', 0),               undef, 'script_run with no check of success, returns undef when not waiting');

    $fake_exit = 1234;
    is(background_script_run('sleep 10'),                  '1234', 'background_script_run returns a PID');
    is(background_script_run('sleep 10', output => 'foo'), '1234', 'background_script_run with output returns valid PID');
};

subtest 'check_assert_screen' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(_handle_found_needle => sub { return $_[0] });

    my $mock_tinycv = Test::MockModule->new('tinycv');
    $mock_tinycv->redefine(from_ppm => sub($) { return bless({} => __PACKAGE__); });

    throws_ok(sub { assert_screen(''); }, qr/no tags specified/, 'error if tag(s) is falsy scalar');
    throws_ok(sub { assert_screen([]); }, qr/no tags specified/, 'error if tag(s) is empty array');

    my $current_test = $autotest::current_test;
    $autotest::current_test = undef;
    throws_ok(sub { assert_screen('foo', 1); }, qr/current_test undefined/, 'error if current test undefined');
    $autotest::current_test = $current_test;

    $mock_bmwqemu->unmock('log_call');
    stderr_like {
        is_deeply(assert_screen('foo', 1), {needle => 1}, 'expected and found MATCH reported')
    }
    qr/assert_screen(.*timeout=1)/;
    stderr_like { assert_screen('foo', 3, timeout => 2) } qr/timeout=2/, 'named over positional';
    stderr_like { assert_screen('foo') } qr/timeout=30/, 'default timeout';
    stderr_like { assert_screen('foo', no_wait => 1) } qr/no_wait=1/, 'no wait option';
    stderr_like { check_screen('foo') } qr/timeout=0/, 'check_screen with timeout of 0';
    stderr_like { check_screen('foo', 42) } qr/timeout=42/, 'check_screen with timeout variable';
    stderr_like { check_screen([qw(foo bar)], 42) } qr/timeout=42/, 'check_screen with multiple tags';
    $mock_bmwqemu->noop('log_call');

    $fake_needle_found = 0;
    is($report_timeout_called, 0, 'report_timeout not called yet');

    subtest 'handle check_screen timeout' => sub {
        $cmds = [];
        $autotest::current_test->{details} = [];

        ok(!check_screen('foo', 3, timeout => 2));
        is($report_timeout_called, 1, 'report_timeout called for check_screen');
        is_deeply($cmds, [{
                    timeout   => 2,
                    no_wait   => undef,
                    check     => 1,
                    mustmatch => 'foo',
                    cmd       => 'check_screen',
                },
                {
                    cmd   => 'is_configured_to_pause_on_timeout',
                    check => 1,
                },
                {
                    check => 1,
                    cmd   => 'report_timeout',
                    msg   => 'match=fake,tags timed out after 2 (check_screen)',
                    tags  => [qw(fake tags)],
                }], 'RPC messages correct (especially check == 1)') or diag explain $cmds;
        is_deeply($autotest::current_test->{details}, [
                {
                    result     => 'unk',
                    screenshot => 'basetest-15.png',
                    frametime  => [qw(1.75 1.79)],
                    tags       => [qw(fake tags)],
                }
        ], 'result (to create a new neede from) has been added')
          or diag explain $autotest::current_test->{details};
    };

    $report_timeout_called = 0;

    subtest 'handle assert_screen timeout' => sub {
        $cmds = [];

        # simulate that we don't want to pause at all and just let it fail
        throws_ok(sub { assert_screen('foo', 3, timeout => 2) },
            qr/no candidate needle with tag\(s\) \'foo\' matched/,
            'no candidate needle matched tags'
        );
        is($report_timeout_called, 1, 'report_timeout called on timeout');
        is_deeply($cmds, [{
                    timeout   => 2,
                    no_wait   => undef,
                    check     => 0,
                    mustmatch => 'foo',
                    cmd       => 'check_screen',
                },
                {
                    cmd   => 'is_configured_to_pause_on_timeout',
                    check => 0,
                },
                {
                    check => 0,
                    cmd   => 'report_timeout',
                    msg   => 'match=fake,tags timed out after 2 (assert_screen)',
                    tags  => [qw(fake tags)],
                }], 'RPC messages correct (especially check == 0)') or diag explain $cmds;

        # simulate that we want to pause after timeout in the first place but fail as usual on 2nd attempt
        $report_timeout_called = 0;
        $fake_pause_on_timeout = 1;
        throws_ok(sub { assert_screen('foo', 3, timeout => 2) },
            qr/no candidate needle with tag\(s\) \'foo\' matched/,
            'no candidate needle matched tags'
        );
        is($report_timeout_called, 2, 'report_timeout called once, and then again after pause');

        # simulate a match after pausing due to timeout
        $report_timeout_called         = 0;
        $fake_pause_on_timeout         = 1;
        $fake_needle_found_after_pause = 1;
        assert_screen('foo', 3, timeout => 2);
        is($report_timeout_called, 1, 'report_timeout called only once');
    };
};

ok(save_screenshot);

is(match_has_tag,        undef, 'match_has_tag on no value -> undef');
is(match_has_tag('foo'), undef, 'match_has_tag on not matched tag -> undef');
subtest 'assert_and_click' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    my @areas        = ({x => 1, y => 2, w => 10, h => 20});
    $mock_testapi->redefine(assert_screen => {area => \@areas});

    $cmds = [];
    ok(assert_and_click('foo'));
    is_deeply($cmds, [
            {
                cmd => 'backend_get_last_mouse_set'
            },
            {
                cmd => 'backend_mouse_set',
                x   => 6,
                y   => 12
            },
            {
                bstate => 1,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
            {
                bstate => 0,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
            {
                cmd => 'backend_mouse_set',
                x   => 100,
                y   => 100
            },
    ], 'assert_and_click succeeds and move to old mouse set') or diag explain $cmds;

    $cmds = [];
    push(@areas, {x => 50, y => 60, w => 22, h => 20, click_point => {xpos => 5, ypos => 7}});
    ok(assert_and_click('foo'));
    is_deeply($cmds->[1], {
            cmd => 'backend_mouse_set',
            x   => 55,
            y   => 67,
    }, 'assert_and_click clicks at the click point') or diag explain $cmds;

    $cmds  = [];
    @areas = ({x => 50, y => 60, w => 22, h => 20, click_point => 'center'}, {x => 0, y => 0, w => 0, h => 0});
    ok(assert_and_click('foo'));
    is_deeply($cmds->[1], {
            cmd => 'backend_mouse_set',
            x   => 61,
            y   => 70,
    }, 'assert_and_click clicks at the  click point specified as "center"') or diag explain $cmds;

    is_deeply($cmds->[-1], {cmd => 'backend_mouse_set', x => 100, y => 100}, 'assert_and_click succeeds and move to old mouse set');

    ok(assert_and_click('foo', mousehide => 1));
    is_deeply($cmds->[-1], {cmd => 'backend_mouse_hide', offset => 0}, 'assert_and_click succeeds and hides mouse with mousehide => 1');

    ok(assert_and_click('foo', button => 'right'));
    is_deeply($cmds->[-2], {bstate => 0,                   button => 'right', cmd => 'backend_mouse_button'}, 'assert_and_click succeeds with right click');
    is_deeply($cmds->[-1], {cmd    => 'backend_mouse_set', x      => 100,     y   => 100}, 'assert_and_click succeeds and move to old mouse set');
};

subtest 'assert_and_dclick' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(assert_screen => {area => [{x => 1, y => 2, w => 3, h => 4}]});
    ok(assert_and_dclick('foo', mousehide => 1));
    for (-2, -4) {
        is_deeply($cmds->[$_], {bstate => 0, button => 'left', cmd => 'backend_mouse_button'}, 'assert_and_dclick succeeds with bstate => 0');
    }
    for (-3, -5) {
        is_deeply($cmds->[$_], {bstate => 1, button => 'left', cmd => 'backend_mouse_button'}, 'assert_and_dclick succeeds with bstate => 1');
    }
    is_deeply($cmds->[-1], {cmd => 'backend_mouse_hide', offset => 0}, 'assert_and_dclick succeeds and hides mouse with mousehide => 1');
};

subtest 'record_info' => sub {
    ok(record_info('my title', "my output\nnext line"), 'simple call');
    ok(record_info('my title', 'output', result => 'ok', resultname => 'foo'), 'all arguments');
    like(exception { record_info('my title', 'output', result => 'not supported', resultname => 'foo') }, qr/unsupported/, 'invalid result');
};

sub script_output_test ($is_serial_terminal) {
    my $mock_testapi = Test::MockModule->new('testapi');
    $testapi::serialdev = 'null';
    $mock_testapi->redefine(type_string        => sub { return });
    $mock_testapi->redefine(send_key           => sub { return });
    $mock_testapi->redefine(hashed_string      => sub { return 'XXX' });
    $mock_testapi->redefine(is_serial_terminal => sub { return $is_serial_terminal });

    $mock_testapi->redefine(wait_serial => sub { return "XXXfoo\nSCRIPT_FINISHEDXXX-0-" });
    is(script_output('echo foo'), 'foo', 'sucessfull retrieves output of script');

    $mock_testapi->redefine(wait_serial => sub { return 'SCRIPT_FINISHEDXXX-0-' });
    is(script_output('foo'), '', 'calling script_output does not fail if script returns with success');

    $mock_testapi->redefine(wait_serial => sub { return "This is simulated output on the serial device\nXXXfoo\nSCRIPT_FINISHEDXXX-0-\nand more here" });
    is(script_output('echo foo'), 'foo', 'script_output return only the actual output of the script');

    $mock_testapi->redefine(wait_serial => sub { return "XXXfoo\nSCRIPT_FINISHEDXXX-1-" });
    is(script_output('echo foo', undef, proceed_on_failure => 1), 'foo', 'proceed_on_failure=1 retrieves retrieves output of script and do not die');

    $mock_testapi->redefine(wait_serial => sub { return 'none' if (shift !~ m/SCRIPT_FINISHEDXXX-\\d\+-/) });
    like(exception { script_output('timeout'); }, qr/timeout/, 'die expected with timeout');

    subtest 'script_output check error codes' => sub {
        for my $ret ((1, 10, 100, 255)) {
            $mock_testapi->redefine(wait_serial => sub { return "XXXfoo\nSCRIPT_FINISHEDXXX-$ret-" });
            like(exception { script_output('false'); }, qr/script failed/, "script_output die expected on exitcode $ret");
        }
    };

    $mock_testapi->redefine(wait_serial => sub {
            my ($regex, %args) = @_;
            is($args{quiet}, undef, 'Check default quiet argument');
            if ($regex =~ m/SCRIPT_FINISHEDXXX-\\d\+-/) {
                is($args{timeout}, 30, 'pass $wait value to wait_serial');
            }
            return "XXXfoo\nSCRIPT_FINISHEDXXX-0-";
    });
    is(script_output('echo foo', 30),            'foo', '');
    is(script_output('echo foo', timeout => 30), 'foo', '');

    $mock_testapi->redefine(wait_serial => sub {
            my ($regex, %args) = @_;
            is($args{quiet}, 1, 'Check quiet argument');
            return "XXXfoo\nSCRIPT_FINISHEDXXX-0-";
    });
    is(script_output('echo foo', quiet => 1), 'foo', '');
}

subtest 'script_output' => sub {
    subtest('Test with is_serial_terminal==0', \&script_output_test, 0);
    subtest('Test with is_serial_terminal==1', \&script_output_test, 1);
};

subtest 'validate_script_output' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(script_output => sub { return 'output'; });
    ok(!validate_script_output('script', sub { m/output/ }), 'validating output with default timeout');
    ok(!validate_script_output('script', qr/output/),        'validating output with regex and default timeout');
    ok(!validate_script_output('script', sub { m/output/ }, 30), 'specifying timeout');
    like(
        exception {
            validate_script_output('script', sub { m/error/ });
        },
        qr/output not validating/
    );
    like(
        exception {
            validate_script_output('script', ['Invalid parameter']);
        },
        qr/coderef or regexp/
    );
};

subtest 'wait_still_screen & assert_still_screen' => sub {
    $mod->redefine(
        read_json => sub {
            return {ret => {sim => 999}};
        });
    $mock_bmwqemu->noop('log_call');
    ok(wait_still_screen,                                                                     'default arguments');
    ok(wait_still_screen(3),                                                                  'still time specified');
    ok(wait_still_screen(2, 4),                                                               'still time and timeout');
    ok(wait_still_screen(stilltime => 2, no_wait => 1),                                       'no_wait option can be specified');
    ok(wait_still_screen(stilltime => 2, timeout => 5, no_wait => 1, similarity_level => 30), 'Add similarity_level & timeout');
    my $ret;
    stderr_like { wait_still_screen(timeout => 4, no_wait => 1) } qr/[warn].*wait_still_screen.*timeout.*below stilltime/, 'log';
    ok(!$ret,                                 'two named args, with timeout below stilltime - which will always return false');
    ok(wait_still_screen(1, 2, timeout => 3), 'named over positional');
    ok(assert_still_screen,                   'default arguments to assert_still_screen');
    my $testapi = Test::MockModule->new('testapi');
    $testapi->redefine(wait_still_screen => sub { die "wait_still_screen(@_)" });
    like(exception { assert_still_screen similarity_level => 9999; }, qr/wait_still_screen\(similarity_level 9999\)/,
        'assert_still_screen forwards arguments to wait_still_screen');
};

subtest 'test console::console argument settings' => sub {
    # test console's methods manually since promoting the commands is mocked in this test
    my $console = consoles::console->new('dummy-console', {tty => 3});
    is($console->{args}->{tty}, 3);
    $console->set_tty(42);
    is($console->{args}->{tty}, 42);
    $console->set_args(tty => 43, foo => 'bar');
    is($console->{args}->{tty}, 43);
    is($console->{args}->{foo}, 'bar');
};

subtest 'check_assert_shutdown' => sub {
    # Test cases, when shutdown is finished before timeout is hit
    $mod->redefine(
        read_json => sub {
            return {ret => 1};
        });
    ok(check_shutdown, 'check_shutdown should return "true" if shutdown finished before timeout is hit');
    is(assert_shutdown, undef, 'assert_shutdown should return "undef" if shutdown finished before timeout is hit');
    $mod->redefine(
        read_json => sub {
            return {ret => -1};
        });
    ok(check_shutdown, 'check_shutdown should return "true" if backend does not implement is_shutdown');
    is(assert_shutdown, undef, 'assert_shutdown should return "undef" if backend does not implement is_shutdown');
    # Test cases, when shutdown is not finished if timeout is hit
    $mod->redefine(
        read_json => sub {
            return {ret => 0};
        });
    is(check_shutdown, 0, 'check_shutdown should return "false" if timeout is hit');
    throws_ok { assert_shutdown } qr/Machine didn't shut down!/, 'assert_shutdown should throw exception if timeout is hit';

};

subtest 'compat_args' => sub {
    my %def_args = (a => 'X', b => 123, c => undef);
    is_deeply({testapi::compat_args(\%def_args, [], a => 'X', b => 123)}, \%def_args, 'Check defaults 1');
    is_deeply({testapi::compat_args(\%def_args, [], a => 'X')},           \%def_args, 'Check defaults 2');
    is_deeply({testapi::compat_args(\%def_args, [])},                     \%def_args, 'Check defaults 3');

    is_deeply({testapi::compat_args(\%def_args, ['a'], a => 'X', b => 123)}, \%def_args, 'Check named parameter 1');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b'], a => 'X')},      \%def_args, 'Check named parameter 2');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b', 'c'])},           \%def_args, 'Check named parameter 3');

    is_deeply({testapi::compat_args(\%def_args, [], a => 'Y', b => 666, c => 23)}, {a => 'Y', b => 666, c => 23},           'Check named parameter 4');
    is_deeply({testapi::compat_args(\%def_args, [], a => 'Y', b => 666)},          {a => 'Y', b => 666, c => $def_args{c}}, 'Check named parameter 5');
    is_deeply({testapi::compat_args(\%def_args, [], a => 'Y')},                    {a => 'Y', b => $def_args{b}, c => $def_args{c}}, 'Check named parameter 6');

    is_deeply({testapi::compat_args(\%def_args, ['a'], 'Y', b => 666, c => 23)}, {a => 'Y', b => 666, c => 23}, 'Check mixed parameter 1');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b'], 'Y', 666, c => 23)}, {a => 'Y', b => 666, c => 23}, 'Check mixed parameter 2');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b', 'c'], 'Y', 666, 23)}, {a => 'Y', b => 666, c => 23}, 'Check mixed parameter 3');

    is_deeply({testapi::compat_args(\%def_args, ['a'], 'Y', c => 23, b => 666)},     {a => 'Y', b => 666, c => 23}, 'Check mixed parameter 4');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b'], 'Y', undef, c => 23)},   {a => 'Y', b => $def_args{b}, c => 23}, 'Check mixed parameter 5');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b'], 'Y', undef, b => 23)},   {a => 'Y', b => 23, c => $def_args{c}}, 'Check mixed parameter 6');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b', 'c'], undef, 666, 23)},   {a => $def_args{a}, b => 666, c => 23}, 'Check mixed parameter 7');
    is_deeply({testapi::compat_args(\%def_args, ['a', 'b', 'c'], undef, undef, 23)}, {a => $def_args{a}, b => $def_args{b}, c => 23}, 'Check mixed parameter 8');
    is_deeply({testapi::compat_args(\%def_args, ['c', 'b', 'a'], undef, undef, 23)}, {a => 23, b => $def_args{b}, c => $def_args{c}}, 'Check mixed parameter 9');
    is_deeply({testapi::compat_args(\%def_args, ['c', 'b', 'a'], 666, undef, 23)},   {a => 23, b => $def_args{b}, c => 666}, 'Check mixed parameter 10');

    is_deeply({testapi::compat_args(\%def_args, ['a'], 'Y', c => undef, b => 666)},   {a => 'Y', b => 666, c => $def_args{c}}, 'Undef in parameter 1');
    is_deeply({testapi::compat_args(\%def_args, ['a'], 'Y', c => undef, b => undef)}, {a => 'Y', b => $def_args{b}, c => $def_args{c}}, 'Undef in parameter 2');
    is_deeply({testapi::compat_args(\%def_args, ['a'], undef, c => undef, b => undef)}, {a => $def_args{a}, b => $def_args{b}, c => $def_args{c}}, 'Undef in parameter 3');

    is_deeply({testapi::compat_args(\%def_args, [], a => 'Y', b => 666, k => 5)}, {a => 'Y', b => 666, c => $def_args{c}, k => 5}, 'Additional parameter 1');
    is_deeply({testapi::compat_args(\%def_args, [], k => 5)}, {a => $def_args{a}, b => $def_args{b}, c => $def_args{c}, k => 5}, 'Additional parameter 2');
    is_deeply({testapi::compat_args(\%def_args, ['c'], 666, k => 5)}, {a => $def_args{a}, b => $def_args{b}, c => 666, k => 5}, 'Additional parameter 3');

    like(warning { testapi::compat_args(\%def_args, [], a => 'Z', 'outch') }->[0], qr/^Odd number of arguments/, 'Warned on Odd number 1');
    like(warning { testapi::compat_args(\%def_args, [], 'outch') }->[0],           qr/^Odd number of arguments/, 'Warned on Odd number 2');
};

subtest 'check quiet option on script runs' => sub {
    $bmwqemu::vars{_QUIET_SCRIPT_CALLS} = 1;
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->redefine(wait_serial => sub {
            my ($regex, %args) = @_;
            is($args{quiet}, 1, 'Check default quiet argument');
            return "XXXfoo\nSCRIPT_FINISHEDXXX-0-";
    });
    is(script_output('echo foo', 30), 'foo', 'script_output with _QUIET_SCRIPT_CALLS=1 expects command output');
    is(script_run('true'),            '0',   'script_run with _QUIET_SCRIPT_CALLS=1');
    is(assert_script_run('true'),     undef, 'assert_script_run with _QUIET_SCRIPT_CALLS=1');
    ok(!validate_script_output('script', sub { m/output/ }), 'validate_script_output with _QUIET_SCRIPT_CALLS=1');

    $mock_testapi->redefine(wait_serial => sub {
            my ($regex, %args) = @_;
            is($args{quiet}, 0, 'Check default quiet argument');
            return "XXXfoo\nSCRIPT_FINISHEDXXX-0-";
    });
    is(script_output('echo foo', quiet => 0), 'foo', 'script_output with _QUIET_SCRIPT_CALLS=1 and quiet=>0');
    is(script_run('true', quiet => 0),        '0',   'script_run with _QUIET_SCRIPT_CALLS=1 and quiet=>0');
    is(assert_script_run('true', quiet => 0), undef, 'assert_script_run with _QUIET_SCRIPT_CALLS=1 and quiet=>0');
    ok(!validate_script_output('script', sub { m/output/ }, quiet => 0), 'validate_script_output with _QUIET_SCRIPT_CALLS=1 and quiet=>0');
    delete $bmwqemu::vars{_QUIET_SCRIPT_CALLS};
};

subtest 'autoinst_url' => sub {
    $bmwqemu::vars{QEMUPORT}        = 0;
    $bmwqemu::vars{JOBTOKEN}        = '';
    $bmwqemu::vars{WORKER_HOSTNAME} = 'my_worker_host';
    is(autoinst_url('foo'), 'http://my_worker_host:1/foo', 'autoinst_url returns reasonable URL based on WORKER_HOSTNAME');
    $bmwqemu::vars{BACKEND} = 'qemu';
    is(autoinst_url('foo'), 'http://10.0.2.2:1/foo', 'autoinst_url returns static IP for qemu');
    $bmwqemu::vars{QEMU_HOST_IP} = '192.168.42.1';
    is(autoinst_url('foo'), 'http://192.168.42.1:1/foo', 'autoinst_url returns configured static IP');
    $bmwqemu::vars{AUTOINST_URL_HOSTNAME} = 'localhost';
    is(autoinst_url('foo'), 'http://localhost:1/foo', 'we can configure the hostname that autoinst_url returns');
};

subtest '_calculate_clickpoint' => sub {
    my %fake_needle = (
        area => [{x => 10, y => 10, w => 20, h => 30}],
    );
    my %fake_needle_area = (x    => 100, y    => 100, w => 50, h => 40);
    my %fake_click_point = (xpos => 20,  ypos => 10);

    # Everything is provided.
    my ($x, $y) = testapi::_calculate_clickpoint(\%fake_needle, \%fake_needle_area, \%fake_click_point);
    is $x, 120, 'clickpoint x';
    is $y, 110, 'clickpoint y';

    # Everything is provided but the click point is 'center'
    ($x, $y) = testapi::_calculate_clickpoint(\%fake_needle, \%fake_needle_area, "center");
    is $x, 125, 'clickpoint x centered';
    is $y, 120, 'clickpoint y centered';

    # Just the area is provided and no click point.
    ($x, $y) = testapi::_calculate_clickpoint(\%fake_needle, \%fake_needle_area);
    is $x, 125, 'clickpoint x from area';
    is $y, 120, 'clickpoint y from area';

    # Just the needle is provided and no area and click point.
    ($x, $y) = testapi::_calculate_clickpoint(\%fake_needle);
    is $x, 20, 'clickpoint x from needle';
    is $y, 25, 'clickpoint y from needle';
};

subtest 'mouse_drag' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    my @area         = ({x => 100, y => 100, w => 20, h => 20});
    $mock_testapi->redefine(assert_screen => {area => \@area});

    my ($startx, $starty) = (0,   0);
    my ($endx,   $endy)   = (200, 200);
    my $button = "left";
    $cmds = [];
    # Startpoint from a needle. Endpoint coordinates.
    mouse_drag(startpoint => 'foo', endx => $endx, endy => $endy, button => $button, timeout => 30);
    is_deeply($cmds, [
            {
                cmd => 'backend_mouse_set',
                x   => 110,
                y   => 110
            },
            {
                bstate => 1,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
            {
                cmd => 'backend_mouse_set',
                x   => 200,
                y   => 200
            },
            {
                bstate => 0,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
    ], 'mouse drag (startpoint defined by a needle)') or diag explain $cmds;

    # Startpoint from coordinates, endpoint from a needle.
    $cmds = [];
    mouse_drag(endpoint => 'foo', startx => $startx, starty => $starty, button => $button, timeout => 30);
    is_deeply($cmds, [
            {
                cmd => 'backend_mouse_set',
                x   => 0,
                y   => 0
            },
            {
                bstate => 1,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
            {
                cmd => 'backend_mouse_set',
                x   => 110,
                y   => 110
            },
            {
                bstate => 0,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
    ], 'mouse drag (endpoint defined by a needle)') or diag explain $cmds;

    # Using coordinates only.
    $cmds = [];
    mouse_drag(endx => $endx, endy => $endy, startx => $startx, starty => $starty, button => $button, timeout => 30);
    is_deeply($cmds, [
            {
                cmd => 'backend_mouse_set',
                x   => 0,
                y   => 0
            },
            {
                bstate => 1,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
            {
                cmd => 'backend_mouse_set',
                x   => 200,
                y   => 200
            },
            {
                bstate => 0,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
    ], 'mouse drag (start and endpoints defined by coordinates)') or diag explain $cmds;

    # Both needle and coordinates provided for startpoint (coordinates should win).
    $cmds = [];
    mouse_drag(startpoint => "foo", endx => $endx, endy => $endy, startx => $startx, starty => $starty, button => $button, timeout => 30);
    is_deeply($cmds, [
            {
                cmd => 'backend_mouse_set',
                x   => 0,
                y   => 0
            },
            {
                bstate => 1,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
            {
                cmd => 'backend_mouse_set',
                x   => 200,
                y   => 200
            },
            {
                bstate => 0,
                button => 'left',
                cmd    => 'backend_mouse_button'
            },
    ], 'mouse drag (redundant definiton by a needle)') or diag explain $cmds;
};

done_testing;

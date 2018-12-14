#!/usr/bin/perl

use strict;
use warnings;

use consoles::console;
use File::Temp;
use OpenQA::Isotovideo::Interface;
use Test::More;
use Test::Output;
use Test::Fatal;
use Test::Mock::Time;
use Test::Warnings;
use Test::Exception;
use Test::Exception;
use Scalar::Util 'looks_like_number';

BEGIN {
    unshift @INC, '..';
}

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
sub write_with_thumbnail {
}

sub fake_send_json {
    my ($to_fd, $cmd) = @_;
    push(@$cmds, $cmd);
}

sub fake_read_json {
    my ($fd) = @_;
    my $lcmd = $cmds->[-1];
    my $cmd  = $lcmd->{cmd};
    if ($cmd eq 'backend_wait_serial') {
        my $str = $lcmd->{regexp};
        $str =~ s,\\d\+,$fake_exit,;
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
        return {ret => {x => -1, y => -1}};
    }
    else {
        print "not implemented \$cmd: $cmd\n";
    }
    return {};
}

$mod->mock(send_json => \&fake_send_json);
$mod->mock(read_json => \&fake_read_json);

use testapi qw(is_serial_terminal :DEFAULT);
use basetest;
my $mock_basetest = Test::MockModule->new('basetest');
$mock_basetest->mock(_result_add_screenshot => sub { my ($self, $result) = @_; });
$autotest::current_test = basetest->new();

# we have to mock out wait_screen_change for the type_string tests
# that use it, as it doesn't work with the fake send_json and read_json
my $mod2 = Test::MockModule->new('testapi');

sub fake_wait_screen_change(&@) {
    my ($callback, $timeout) = @_;
    $callback->() if $callback;
}

$mod2->mock(wait_screen_change => \&fake_wait_screen_change);

type_string 'hallo';
is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 250, text => 'hallo'}]);
$cmds = [];

type_string 'hallo', 4;
is_deeply($cmds, [{cmd => 'backend_type_string', max_interval => 4, text => 'hallo'}]);
$cmds = [];

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

subtest 'type_string with wait_still_screen' => sub {
    my $wait_still_screen_called = 0;
    my $module                   = Test::MockModule->new('testapi');
    $module->mock(wait_still_screen => sub { $wait_still_screen_called = 1; });
    type_string 'hallo', wait_still_screen => 1;
    is_deeply($cmds, [{cmd => 'backend_type_string', text => 'hallo', max_interval => 250}]);
    $cmds = [];
    ok($wait_still_screen_called, 'wait still screen should have been called');
};


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

my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
$mock_bmwqemu->mock(result_dir => File::Temp->newdir());

is($autotest::current_test->{dents}, 0, 'no soft failures so far');
stderr_like(\&record_soft_failure, qr/record_soft_failure\(reason=undef\)/, 'soft failure recorded in log');
is($autotest::current_test->{dents}, 1, 'soft failure recorded');
stderr_like(sub { record_soft_failure('workaround for bug#1234') }, qr/record_soft_failure.*reason=.*workaround for bug#1234.*/, 'soft failure with reason');
is($autotest::current_test->{dents}, 2, 'another');
my $details    = $autotest::current_test->{details}[-1];
my $details_ok = is($details->{title}, 'Soft Failed', 'title for soft failure added');
$details_ok &= is($details->{result}, 'softfail', 'result correct');
$details_ok &= like($details->{text}, qr/basetest-[0-9]+.*txt/, 'file for soft failure added');
diag explain $details unless $details_ok;

require distribution;
testapi::set_distribution(distribution->new());
select_console('a-console');
is(is_serial_terminal, 0,           'Not a serial terminal');
is(current_console,    'a-console', 'Current console is the a-console');

subtest 'script_run' => sub {
    my $module = Test::MockModule->new('bmwqemu');
    # just save ourselves some time during testing
    $module->mock(wait_for_one_more_screenshot => sub { sleep 0; });

    $testapi::serialdev = 'null';

    is(assert_script_run('true'), undef, 'nothing happens on success');
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
    is(script_run('true'), '0', 'script_run with no check of success, returns exit code');
    $fake_exit = 1;
    is(script_run('false'), '1', 'script_run with no check of success, returns exit code');
    is(script_run('false', 0), undef, 'script_run with no check of success, returns undef when not waiting');
};

subtest 'check_assert_screen' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->mock(_handle_found_needle => sub { return $_[0] });

    my $mock_tinycv = Test::MockModule->new('tinycv');
    $mock_tinycv->mock(from_ppm => sub { return bless({} => __PACKAGE__); });

    stderr_like {
        is_deeply(assert_screen('foo', 1), {needle => 1}, 'expected and found MATCH reported');
    }
    qr/assert_screen(.*timeout=1)/;
    stderr_like { assert_screen('foo', 3, timeout => 2) } qr/timeout=2/, 'named over positional';
    stderr_like { assert_screen('foo') } qr/timeout=30/, 'default timeout';
    stderr_like { assert_screen('foo', no_wait => 1) } qr/no_wait=1/, 'no wait option';
    stderr_like { check_screen('foo') } qr/timeout=0/, 'check_screen with timeout of 0';
    stderr_like { check_screen('foo', 42) } qr/timeout=42/, 'check_screen with timeout variable';

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
                    screenshot => 'basetest-17.png',
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
    $mock_testapi->mock(assert_screen => {area => [{x => 1, y => 2, w => 3, h => 4}]});
    ok(assert_and_click('foo'));
    is_deeply($cmds->[-1], {cmd => 'backend_mouse_hide', offset => 0}, 'assert_and_click succeeds and hides mouse again -> undef return');
};

subtest 'record_info' => sub {
    ok(record_info('my title', "my output\nnext line"), 'simple call');
    ok(record_info('my title', 'output', result => 'ok', resultname => 'foo'), 'all arguments');
    like(exception { record_info('my title', 'output', result => 'not supported', resultname => 'foo') }, qr/unsupported/, 'invalid result');
};

sub script_output_test {
    my $is_serial_terminal = shift;
    my $mock_testapi       = Test::MockModule->new('testapi');
    $testapi::serialdev = 'null';
    $mock_testapi->mock(type_string        => sub { return });
    $mock_testapi->mock(send_key           => sub { return });
    $mock_testapi->mock(hashed_string      => sub { return 'XXX' });
    $mock_testapi->mock(is_serial_terminal => sub { return $is_serial_terminal });

    $mock_testapi->mock(wait_serial => sub { return "XXXfoo\nSCRIPT_FINISHEDXXX-0-" });
    is(script_output('echo foo'), 'foo', 'sucessfull retrieves output of script');

    $mock_testapi->mock(wait_serial => sub { return 'SCRIPT_FINISHEDXXX-0-' });
    is(script_output('foo'), '', 'calling script_output does not fail if script returns with success');

    $mock_testapi->mock(wait_serial => sub { return "This is simulated output on the serial device\nXXXfoo\nSCRIPT_FINISHEDXXX-0-\nand more here" });
    is(script_output('echo foo'), 'foo', 'script_output return only the actual output of the script');

    $mock_testapi->mock(wait_serial => sub { return "XXXfoo\nSCRIPT_FINISHEDXXX-1-" });
    is(script_output('echo foo', undef, proceed_on_failure => 1), 'foo', 'proceed_on_failure=1 retrieves retrieves output of script and do not die');

    $mock_testapi->mock(wait_serial => sub { return 'none' if (shift !~ m/SCRIPT_FINISHEDXXX-\\d\+-/) });
    like(exception { script_output('timeout'); }, qr/timeout/, 'die expected with timeout');

    subtest 'script_output check error codes' => sub {
        for my $ret ((1, 10, 100, 255)) {
            $mock_testapi->mock(wait_serial => sub { return "XXXfoo\nSCRIPT_FINISHEDXXX-$ret-" });
            like(exception { script_output('false'); }, qr/script failed/, "script_output die expected on exitcode $ret");
        }
    };

    $mock_testapi->mock(wait_serial => sub {
            my ($regex, $wait) = @_;
            if ($regex =~ m/SCRIPT_FINISHEDXXX-\\d\+-/) {
                is($wait, 30, 'pass $wait value to wait_serial');
            }
            return "XXXfoo\nSCRIPT_FINISHEDXXX-0-";
    });
    is(script_output('echo foo', 30), 'foo', '');
}

subtest 'script_output' => sub {
    subtest('Test with is_serial_terminal==0', \&script_output_test, 0);
    subtest('Test with is_serial_terminal==1', \&script_output_test, 1);
};

subtest 'validate_script_output' => sub {
    my $mock_testapi = Test::MockModule->new('testapi');
    $mock_testapi->mock(script_output => sub { return 'output'; });
    ok(!validate_script_output('script', sub { m/output/ }), 'validating output with default timeout');
    ok(!validate_script_output('script', sub { m/output/ }, 30), 'specifying timeout');
    like(
        exception {
            validate_script_output('script', sub { m/error/ });
        },
        qr/output not validating/
    );
};

subtest 'wait_still_screen' => sub {
    $mod->mock(
        read_json => sub {
            return {ret => {sim => 999}};
        });
    ok(wait_still_screen,    'default arguments');
    ok(wait_still_screen(3), 'still time specified');
    ok(wait_still_screen(2, 4), 'still time and timeout');
    ok(wait_still_screen(stilltime => 2, no_wait => 1), 'no_wait option can be specified');
    ok(!wait_still_screen(timeout => 4, no_wait => 1), 'two named args, with timeout below stilltime - which will always return false');
    ok(wait_still_screen(1, 2, timeout => 3), 'named over positional');
};

subtest 'set console tty and other args' => sub {
    # ensure previously emitted commands are cleared
    $cmds = ();

    console->set_tty(4);
    console->set_args(tty => 5, foo => 'bar');

    is_deeply(
        $cmds,
        [
            {
                cmd      => 'backend_proxy_console_call',
                console  => 'a-console',
                function => 'set_tty',
                args     => [4],
            },
            {
                cmd      => 'backend_proxy_console_call',
                console  => 'a-console',
                function => 'set_args',
                args     => ['tty', 5, 'foo', 'bar'],
            },
        ]);

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
    $mod->mock(
        read_json => sub {
            return {ret => 1};
        });
    ok(check_shutdown, 'check_shutdown should return "true" if shutdown finished before timeout is hit');
    is(assert_shutdown, undef, 'assert_shutdown should return "undef" if shutdown finished before timeout is hit');
    $mod->mock(
        read_json => sub {
            return {ret => -1};
        });
    ok(check_shutdown, 'check_shutdown should return "true" if backend does not implement is_shutdown');
    is(assert_shutdown, undef, 'assert_shutdown should return "undef" if backend does not implement is_shutdown');
    # Test cases, when shutdown is not finished if timeout is hit
    $mod->mock(
        read_json => sub {
            return {ret => 0};
        });
    is(check_shutdown, 0, 'check_shutdown should return "false" if timeout is hit');
    throws_ok { assert_shutdown } qr/Machine didn't shut down!/, 'assert_shutdown should throw exception if timeout is hit';

};

done_testing;

# vim: set sw=4 et:

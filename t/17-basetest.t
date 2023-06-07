#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings ':report_warnings';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::Fatal;
use Test::Output qw(combined_like combined_from);
use File::Basename;
use Mojo::File qw(path tempdir);
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(scope_guard);
use MIME::Base64 'encode_base64';
use cv;
use basetest;

cv::init;
require tinycv;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };
mkdir 'testresults';

use basetest;
use needle;

# define 'write_with_thumbnail' to fake image
sub write_with_thumbnail (@) { }

# Anything added to $serial_buffer will be returned by the next call
# to read_serial, used e.g. by basetest::get_new_serial_output.
my $serial_buffer = "";
# Mock the JSON call for read_serial
my $cmds;
my $jsonmod = Test::MockModule->new('myjsonrpc');
$autotest::isotovideo = 1;

my $last_screenshot_data;
my $fake_ignore_failure;
my $suppress_match;
my @reset_consoles;
my @selected_consoles;
sub fake_send_json ($to_fd, $cmd) { push(@$cmds, $cmd) }
sub fake_read_json ($fd) {
    my $lcmd = $cmds->[-1];
    my $cmd = $lcmd->{cmd};
    if ($cmd eq 'read_serial') {
        return {
            serial => substr($serial_buffer, $lcmd->{position}),
            position => length($serial_buffer),
        };
    }
    elsif ($cmd eq 'backend_verify_image') {
        return {ret => {found => {needle => {name => 'foundneedle', file => 'foundneedle.json'}, area => [{x => 1, y => 2, similarity => 100}]}, candidates => []}} unless $suppress_match;
        return {};
    }
    elsif ($cmd eq 'backend_reset_console') {
        push @reset_consoles, $lcmd;
        return {};
    }
    elsif ($cmd eq 'backend_select_console') {
        push @selected_consoles, $lcmd;
        return {};
    }
    elsif ($cmd eq 'backend_last_screenshot_data') {
        return {} unless $last_screenshot_data;
        return {ret => {image => $last_screenshot_data, frame => 1}};
    }
    elsif ($cmd eq 'pause_test_execution') {
        return {ret => {ignore_failure => $fake_ignore_failure}};
    }
    return {};
}

$jsonmod->redefine(send_json => \&fake_send_json);
$jsonmod->redefine(read_json => \&fake_read_json);

my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
$mock_bmwqemu->noop('log_call');

subtest run_post_fail_test => sub {
    my $basetest_class = 'basetest';
    Test::MockModule->new("autotest")->noop('set_current_test');
    my $mock_basetest = Test::MockModule->new($basetest_class);
    $mock_basetest->noop('take_screenshot');
    $mock_basetest->mock(run => sub { die(); });
    my $basetest = bless({
            details => [],
            name => 'foo',
            category => 'category1',
            execute_time => 42,
    }, $basetest_class);
    my $logs = combined_from { dies_ok { $basetest->runtest } 'run_post_fail end up with die' };
    like $logs, qr/Test died/, 'test died';
    like $logs, qr/post fail hooks runtime:/, 'post fail hook ran and its runtime is logged';
    subtest 'expected commands sent' => sub {
        my %pause_on_failure = (cmd => 'pause_test_execution', due_to_failure => 1);
        like delete $cmds->[0]->{reason}, qr/test died: Died at .*17-basetest\.t/, 'reason for pause passed';
        is_deeply $cmds->[0], \%pause_on_failure, 'failure reported to pause if pausing on failures enabled';
        my %test_name_update = (cmd => 'set_current_test', name => 'foo', full_name => 'foo (post fail hook)');
        is_deeply $cmds->[1], \%test_name_update, 'test name updated (to show post fail hook in developer mode)';
    } or diag explain $cmds;

    $bmwqemu::vars{_SKIP_POST_FAIL_HOOKS} = 1;
    combined_like { dies_ok { $basetest->runtest } 'behavior persists regardless of _SKIP_POST_FAIL_HOOKS setting' }
    qr/Test died/, 'test died';

    $bmwqemu::vars{_SKIP_POST_FAIL_HOOKS} = 0;
    $cmds = [];
    $fake_ignore_failure = 1;
    $logs = combined_from { $basetest->runtest };
    like $logs, qr/Test died.*ignoring.*failure via developer mode/s, 'test died but failure ignored';
    unlike $logs, qr/post fail hook/, 'post fail hook not invoked when ignoring failure';
};

subtest modules_test => sub {
    ok(my $basetest = basetest->new('installation'), 'module can be created');
    $basetest->{class} = 'foo';
    $basetest->{fullname} = 'installation-foo';
    ok($basetest->is_applicable, 'module is applicable by default');
    $bmwqemu::vars{EXCLUDE_MODULES} = 'foo,bar';
    ok(!$basetest->is_applicable, 'module can be excluded');
    $bmwqemu::vars{EXCLUDE_MODULES} = 'installation-foo';
    ok(!$basetest->is_applicable, 'model can be excluded by fullname');
    $bmwqemu::vars{EXCLUDE_MODULES} = '';
    $bmwqemu::vars{INCLUDE_MODULES} = 'bar,baz';
    ok(!$basetest->is_applicable, 'modules can be excluded based on a passlist');
    $bmwqemu::vars{INCLUDE_MODULES} = 'bar,baz,foo';
    ok($basetest->is_applicable, 'a passlisted module shows up');
    $bmwqemu::vars{EXCLUDE_MODULES} = 'foo';
    ok(!$basetest->is_applicable, 'passlisted modules are overridden by blocklist');
};

subtest parse_serial_output => sub {
    my $mock_basetest = Test::MockModule->new('basetest');
    # Mock reading of the serial output
    $mock_basetest->redefine(get_new_serial_output => sub {
            return "Serial to match\n1q2w333\nMore text";
    });
    my $basetest = basetest->new('installation');
    my $message;
    $mock_basetest->redefine(record_resultfile => sub {
            my ($self, $title, $output, %nargs) = @_;
            $message = $output;
    });

    $basetest->parse_serial_output_qemu();
    $basetest->{serial_failures} = [
        {type => 'soft', message => 'DoNotMatch', pattern => qr/DoNotMatch/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, undef, 'test result untouched without match');
    is($message, undef, 'test details do not have extra message');

    $basetest->{serial_failures} = [
        {type => 'info', message => 'CPU soft lockup detected', pattern => qr/Serial/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'ok', 'test result set to ok');
    is($message, 'CPU soft lockup detected - Serial error: Serial to match', 'log message matches output');

    $basetest->{result} = 'softfail';
    $basetest->{serial_failures} = [
        {type => 'info', message => 'CPU soft lockup detected', pattern => qr/Serial/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'softfail', 'test result stays at softfail on ok match');

    $basetest->{result} = 'fail';
    $basetest->{serial_failures} = [
        {type => 'info', message => 'CPU soft lockup detected', pattern => qr/Serial/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'fail', 'test result stays at fail on ok match');
    $basetest->{serial_failures} = [
        {type => 'soft', message => 'CPU soft lockup detected', pattern => qr/Serial/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'fail', 'test result stays at fail on softfail match');
    $basetest->{result} = undef;

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'SimplePattern', pattern => qr/Serial/},
    ];

    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'softfail', 'test result set to soft failure');
    is($message, 'SimplePattern - Serial error: Serial to match', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'soft', message => 'Proper regexp', pattern => qr/\d{3}/},
    ];
    $basetest->parse_serial_output_qemu();
    is($basetest->{result}, 'softfail', 'test result set to soft failure');
    is($message, 'Proper regexp - Serial error: 1q2w333', 'log message matches output');

    $basetest->{serial_failures} = [
        {type => 'hard', message => 'Message1', pattern => qr/Serial/},
    ];

    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Got serial hard failure at.*), 'test died hard after match');
    is($basetest->{result}, 'fail', 'test result set to hard failure');

    $basetest->{serial_failures} = [
        {type => 'fatal', message => 'Message1', pattern => qr/Serial/},
    ];

    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Got serial hard failure at.*), 'test died hard after match with fatal type');
    is($basetest->{result}, 'fail', 'test result set to fail after fatal failure');

    $basetest->{serial_failures} = [
        {type => 'non_existent type', message => 'Message1', pattern => qr/Serial/},
    ];
    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Wrong type defined for serial failure.*), 'test died because of wrong serial failure type');
    is($basetest->{result}, 'fail', 'test result set to hard failure');

    $basetest->{serial_failures} = [
        {type => 'soft', message => undef, pattern => qr/Serial/},
    ];
    eval { $basetest->parse_serial_output_qemu() };
    like($@, qr(Message not defined for serial failure for the pattern.*), 'test died because of missing message');
    is($basetest->{result}, 'fail', 'test result set to hard failure');
};

subtest get_new_serial_output => sub {
    my $mock_basetest = Test::MockModule->new('basetest');
    my $basetest = basetest->new('installation');
    $serial_buffer = "Some serial string";
    is($basetest->get_new_serial_output(), 'Some serial string', 'returns serial output');
    is($basetest->get_new_serial_output(), '', 'returns nothing if nothing got added');
    $serial_buffer .= "Some more data";
    is($basetest->get_new_serial_output(), 'Some more data', 'returns new serial output');
};

subtest record_testresult => sub {
    my $basetest_class = 'basetest';
    my $basetest = bless({
            result => undef,
            details => [],
            test_count => 0,
            name => 'test',
    }, $basetest_class);

    is_deeply($basetest->record_testresult(), {result => 'unk'}, 'adding unknown result');
    is($basetest->{result}, undef, 'test result unaffected');
    is($basetest->{test_count}, 1, 'test count increased');

    is_deeply($basetest->record_testresult('ok'), {result => 'ok'}, 'adding "ok" result');
    is($basetest->{result}, 'ok', 'test result is now "ok"');

    is_deeply($basetest->record_testresult('softfail'), {result => 'softfail'}, 'adding "softfail" result');
    is($basetest->{result}, 'softfail', 'test result is now "softfail"');

    is_deeply($basetest->record_testresult('ok'), {result => 'ok'}, 'adding one more "ok" result');
    is($basetest->{result}, 'softfail', 'test result is still "softfail"');

    is_deeply($basetest->record_testresult('fail'), {result => 'fail'}, 'adding "fail" result');
    is($basetest->{result}, 'fail', 'test result is now "fail"');

    is_deeply($basetest->record_testresult('ok'), {result => 'ok'}, 'adding one more "ok" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply($basetest->record_testresult('softfail'), {result => 'softfail'}, 'adding one more "softfail" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply($basetest->record_testresult(), {result => 'unk'}, 'adding one more "unk" result');
    is($basetest->{result}, 'fail', 'test result is still "fail"');

    is_deeply($basetest->record_testresult('softfail', force_status => 1), {result => 'softfail'}, 'adding one more "softfail" result but forcing the status');
    is($basetest->{result}, 'softfail', 'test result was forced to "softfail"');

    is_deeply($basetest->take_screenshot(), {result => 'unk'},
        'unknown result from take_screenshot not added to details');

    $last_screenshot_data = encode_base64(tinycv::new(1, 1)->ppm_data);

    my $res = $basetest->take_screenshot();
    is(ref delete $res->{frametime}, 'ARRAY', 'frametime returned');

    is_deeply($res, {result => 'unk', screenshot => 'test-11.png'},
        'mock image added to details');

    is($basetest->{test_count}, 11, 'test_count accumulated');
    is(scalar @{$basetest->{details}}, 10, 'all details added');
};

subtest 'number of test results is limited' => sub {
    my $total_result_count = basetest::total_result_count;
    ok $total_result_count, 'counter for total results has been incremented before';
    my $basetest = basetest::new('basetest');
    $bmwqemu::vars{MAX_TEST_STEPS} = $total_result_count + 1;
    is_deeply $basetest->record_testresult('ok'), {result => 'ok'}, 'can add one more test result';
    throws_ok { $basetest->record_testresult('ok') } qr/allowed test steps.*exceeded/, 'unable to add a second test result';
    my $state_file = decode_json(path(bmwqemu::STATE_FILE)->slurp);
    is delete $state_file->{result}, 'incomplete', 'job result serialized';
    like delete $state_file->{msg}, qr/allowed test.*exceeded/, 'message for reason serialized';
    is delete $state_file->{component}, 'tests', 'component for reason serialized';
    ok $basetest->{fatal_failure}, 'failure considered fatal';
    $basetest->remove_last_result;
    is_deeply $basetest->record_testresult('ok'), {result => 'ok'}, 'can add one test result again';
};

delete $bmwqemu::vars{MAX_TEST_STEPS};

subtest record_screenmatch => sub {
    my $basetest = basetest->new();
    my $image = bless({} => __PACKAGE__);
    my %match = (
        area => [
            {x => 1, y => 2, w => 3, h => 4, similarity => 0, result => 'ok'},
        ],
        error => 0.128,
        needle => {
            name => 'foo',
            file => 'some/path/foo.json',
            unregistered => 'yes',
        },
    );
    my @tags = (qw(some tags));
    my @failed_needles = (
        {
            error => 1,
            area => [
                {x => 4, y => 3, w => 2, h => 1, similarity => 0, result => 'fail'},
            ],
            needle => {
                name => 'failure',
                file => 'some/path/failure.json',
            },
        },
    );
    my $frame = 24;

    $basetest->record_screenmatch($image, \%match, \@tags, \@failed_needles, $frame);
    is_deeply($basetest->{details}, [
            {
                area => [
                    {
                        x => 1,
                        y => 2,
                        w => 3,
                        h => 4,
                        similarity => 0,
                        result => 'ok',
                    },
                ],
                error => 0.128,
                frametime => [qw(1.00 1.04)],
                needle => 'foo',
                json => 'some/path/foo.json',
                needles => [
                    {
                        area => [
                            {
                                x => 4,
                                y => 3,
                                w => 2,
                                h => 1,
                                similarity => 0,
                                result => 'fail',
                            },
                        ],
                        error => 1,
                        name => 'failure',
                        json => 'some/path/failure.json',
                    }
                ],
                properties => [],
                screenshot => 'basetest-1.png',
                tags => [qw(some tags)],
                result => 'ok',
            }
    ], 'screenmatch detail recorded as expected')
      or diag explain $basetest->{details};

    # check a needle has workaround property
    my $basetest_for_workaround = basetest->new();
    my $misc_needles_dir = dirname(__FILE__) . '/misc_needles/';
    my $needle_file = $misc_needles_dir . "check-workaround-hash-20190522.json";
    my %workaround_match = (
        area => [
            {x => 1, y => 2, w => 3, h => 4, similarity => 0, result => 'ok'},
        ],
        error => 0.25,
        needle => {
            name => 'check-workaround-hash-20190522',
            file => $needle_file,
            properties => [
                {
                    name => 'workaround',
                    value => 'bsc#7654321: this is a test about workaround.',
                }
            ],
        },
    );

    combined_like { $basetest_for_workaround->record_screenmatch($image, \%workaround_match, ['check-workaround-hash'], [], $frame) }
    qr/needle.*is a workaround/, 'needle workaround debug message found';
    is_deeply($basetest_for_workaround->{details}, [
            {
                result => 'softfail',
                title => 'Soft Failed',
                text => 'basetest-3.txt'
            },
            {
                area => [
                    {
                        x => 1,
                        y => 2,
                        w => 3,
                        h => 4,
                        similarity => 0,
                        result => 'ok',
                    },
                ],
                error => 0.25,
                frametime => [qw(1.00 1.04)],
                needle => 'check-workaround-hash-20190522',
                json => $needle_file,
                properties => [
                    {
                        name => 'workaround',
                        value => 'bsc#7654321: this is a test about workaround.',
                    }
                ],
                screenshot => 'basetest-1.png',
                tags => [qw(check-workaround-hash)],
                result => 'softfail',
                dent => 1,
            }
    ], 'screenmatch detail with workaround property recorded as expected')
      or diag explain $basetest_for_workaround->{details};
};

subtest 'register_extra_test_results' => sub {
    my $test = basetest->new('foo');
    $test->{script} = '/tests/foo/bar.pm';

    my $extra_tests = [
        {
            category => 'foo',
            name => 'extra1',
            flags => {},
            script => 'unk'
        },
        {
            category => 'foo',
            name => 'extra2',
            flags => {},
            script => '/test/foo/baz.pm'
        },
        {
            category => 'foo',
            name => 'extra3',
            flags => {},
            script => undef
        }
    ];

    $test->register_extra_test_results($extra_tests);
    is(@{$test->{extra_test_results}}, @{$extra_tests}, 'add extra test results');
    is($test->{extra_test_results}->[0]->{script}, $test->{script}, 'unknown script is replaced with self->{script}.');
    is($test->{extra_test_results}->[1]->{script}, $extra_tests->[1]->{script}, 'existing script is untouched.');
    is($test->{extra_test_results}->[2]->{script}, $test->{script}, 'undefined script is replaced with self->{script}.');
};

subtest 'execute_time' => sub {
    my $basetest_class = 'basetest';
    my $mock_basetest = Test::MockModule->new($basetest_class);
    my $test = basetest->new('foo');
    is($test->{execution_time}, 0, 'the execution time is initiated correctly');
    $mock_basetest->mock(execution_time => 42);
    $mock_basetest->mock(run => undef);
    $mock_basetest->redefine(done => undef);
    combined_like { $test->runtest } qr/finished basetest foo/, 'finish status message found';
    is($test->{execution_time}, 42, 'the execution time is correct');
};

subtest skip_if_not_running => sub {
    my $test = basetest->new();
    $test->{result} = undef;
    $test->skip_if_not_running;
    is($test->{result}, 'skip', 'skip_if_not_running works as expected');
};

subtest capture_filename => sub {
    my $test = basetest->new();
    $test->capture_filename;
    is($test->{wav_fn}, 'basetest-captured.wav', 'capture_filename works as expected');
};

subtest stop_audiocapture => sub {
    my $test = basetest->new();
    my $res = $test->stop_audiocapture();
    is($res->{audio}, undef, 'audio capture stopped');
    is($res->{result}, 'unk', 'audio capture stopped');
    is($test->{details}->[-1], $res, 'result appended to details');
};

$mock_bmwqemu->noop('fctres', 'fctinfo');

subtest verify_sound_image => sub {
    my $test = basetest->new();
    my $res = $test->verify_sound_image("$FindBin::Bin/data/frame1.ppm", 'notapath2', 'check');
    is_deeply($res->{area}, [{x => 1, y => 2, similarity => 100}], 'area was returned') or diag explain $res->{area};
    is($res->{needle}->{file}, 'foundneedle.json', 'needle file was returned');
    is($res->{needle}->{name}, 'foundneedle', 'needle name was returned');
    $suppress_match = 'yes';
    my $details;
    my $mock_test = Test::MockModule->new('basetest');
    $mock_test->mock(record_screenfail => sub { my ($self, %args) = @_; $details = \%args; });
    $res = $test->verify_sound_image("$FindBin::Bin/data/frame1.ppm", "$FindBin::Bin/data/frame2.ppm", 1);
    is($res, undef, 'res is undef as expected') or diag explain $res;
    is($details->{result}, 'unk', 'no needle match: unknown status correct') or diag explain $details;
    $res = $test->verify_sound_image("$FindBin::Bin/data/frame1.ppm", "$FindBin::Bin/data/frame2.ppm", 0);
    is($details->{result}, 'fail', 'no needle match: status fail') or diag explain $details;
    is($details->{overall}, 'fail', 'no needle match: overall fail') or diag explain $details;
};

subtest rollback_activated_consoles => sub {
    my $test = basetest->new();
    $test->{activated_consoles} = ['activated_console'];
    $autotest::last_milestone_console = 'last_milestone_console';
    $test->rollback_activated_consoles;
    is_deeply($test->{activated_consoles}, [], 'activated consoles cleared') or diag explain $test->{activated_consoles};
    is_deeply(\@reset_consoles, [{cmd => 'backend_reset_console', testapi_console => 'activated_console'}], 'activated consoles reset') or diag explain \@reset_consoles;
    is_deeply(\@selected_consoles, [{cmd => 'backend_select_console', testapi_console => 'last_milestone_console'}], 'last milestone console selected') or diag explain \@selected_consoles;
};

$mock_bmwqemu->noop('diag', 'modstate');

subtest search_for_expected_serial_failures => sub {
    $bmwqemu::vars{BACKEND} = 'qemu';
    my $basetest = basetest->new();
    my $mock_basetest = Test::MockModule->new('basetest');
    $mock_basetest->mock(run => sub { die 'test failure' });
    $mock_basetest->mock(parse_serial_output_qemu => sub { $basetest->{result} = 'successfully called function' });
    $basetest->runtest();
    is($basetest->{result}, 'successfully called function', 'search for expected serial failures is working');
};

done_testing;

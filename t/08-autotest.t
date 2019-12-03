#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Output qw(stderr_like combined_from);
use Test::Fatal;
use Test::MockModule;
use File::Basename ();

use autotest;
use bmwqemu;
use OpenQA::Test::RunArgs;

$bmwqemu::vars{CASEDIR} = File::Basename::dirname($0) . '/fake';
# array of messages sent with the fake json_send
my @sent;


like(exception { autotest::runalltests }, qr/ERROR: no tests loaded/, 'runalltests needs tests loaded first');
stderr_like(
    sub {
        like(exception { autotest::loadtest 'does/not/match' }, qr/loadtest.*does not match required pattern/,
            'loadtest catches incorrect test script paths');
    },
    qr/loadtest needs a script below.*is not/,
    'loadtest outputs on stderr'
);

sub loadtest {
    my ($test, $args) = @_;
    stderr_like(sub { autotest::loadtest "tests/$test.pm" }, qr@scheduling $test#?[0-9]* tests/$test.pm|$test already scheduled@, \$args);
}

sub fake_send {
    my ($target, $msg) = @_;
    push @sent, $msg;
}

# find the (first) 'tests_done' message from the @sent array and
# return the 'died' and 'completed' values
sub get_tests_done {
    for my $msg (@sent) {
        if (ref($msg) eq "HASH" && $msg->{cmd} eq 'tests_done') {
            return ($msg->{died}, $msg->{completed});
        }
    }
}

my $mock_jsonrpc = Test::MockModule->new('myjsonrpc');
$mock_jsonrpc->mock(send_json => \&fake_send);
$mock_jsonrpc->mock(read_json => sub { });
my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
$mock_bmwqemu->mock(save_json_file => sub { });
my $mock_basetest = Test::MockModule->new('basetest');
$mock_basetest->mock(_result_add_screenshot => sub { });
# stop run_all from quitting at the end
my $mock_autotest = Test::MockModule->new('autotest', no_auto => 1);
$mock_autotest->mock(_exit => sub { });

my $died;
my $completed;
# we have to define this to *something* so the `close` in run_all
# doesn't crash us
$autotest::isotovideo = 'foo';
stderr_like(sub { autotest::run_all }, qr/ERROR: no tests loaded/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      1, 'run_all with no tests should catch runalltests dying');
is($completed, 0, 'run_all with no tests should not complete');
@sent = [];

loadtest 'start';
loadtest 'next';
is(keys %autotest::tests, 2, 'two tests have been scheduled');
loadtest 'start', 'rescheduling same step later';
is(keys %autotest::tests,                    3,         'three steps have been scheduled (one twice)') || diag explain %autotest::tests;
is($autotest::tests{'tests-start1'}->{name}, 'start#1', 'handle duplicate tests');
is($autotest::tests{'tests-start1'}->{$_}, $autotest::tests{'tests-start'}->{$_}, "duplicate tests point to the same $_")
  for qw(script fullname category class);

stderr_like(sub { autotest::run_all }, qr/finished/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      0, 'start+next+start should not die');
is($completed, 1, 'start+next+start should complete');
@sent = [];

# Test loading snapshots with always_rollback flag. Have to put it here, before loading
# runargs test module, as it fails.
subtest 'test always_rollback flag' => sub {
    # Test that no rollback is triggered when flag is not explicitly set to true
    $mock_basetest->mock(test_flags       => sub { return {milestone => 1}; });
    $mock_autotest->mock(query_isotovideo => sub { return 0; });
    my $reverts_done = 0;
    $mock_autotest->mock(load_snapshot => sub { $reverts_done++; });

    stderr_like(sub { autotest::run_all }, qr/finished/, 'run_all outputs status on stderr');
    ($died, $completed) = get_tests_done;
    is($died,         0, 'start+next+start should not die when always_rollback flag is set');
    is($completed,    1, 'start+next+start should complete when always_rollback flag is set');
    is($reverts_done, 0, "No snapshots loaded when flag is not explicitly set to true");
    $reverts_done = 0;
    @sent         = [];

    # Test that no rollback is triggered if snapshots are not supported
    $mock_basetest->mock(test_flags       => sub { return {always_rollback => 1, milestone => 1}; });
    $mock_autotest->mock(query_isotovideo => sub { return 0; });
    $reverts_done = 0;
    $mock_autotest->mock(load_snapshot => sub { $reverts_done++; });

    stderr_like(sub { autotest::run_all }, qr/finished/, 'run_all outputs status on stderr');
    ($died, $completed) = get_tests_done;
    is($died,         0, 'start+next+start should not die when always_rollback flag is set');
    is($completed,    1, 'start+next+start should complete when always_rollback flag is set');
    is($reverts_done, 0, "No snapshots loaded if snapshots are not supported");
    $reverts_done = 0;
    @sent         = [];

    # Test that snapshot loading is triggered even when tests are successful
    $mock_basetest->mock(test_flags       => sub { return {always_rollback => 1}; });
    $mock_autotest->mock(query_isotovideo => sub { return 1; });
    $reverts_done = 0;

    stderr_like(sub { autotest::run_all }, qr/finished/, 'run_all outputs status on stderr');
    ($died, $completed) = get_tests_done;
    is($died,         0, 'start+next+start should not die when always_rollback flag is set');
    is($completed,    1, 'start+next+start should complete when always_rollback flag is set');
    is($reverts_done, 0, "No snapshots loaded if not test with milestone flag");
    $reverts_done = 0;
    @sent         = [];

    # Test with snapshot available
    $mock_basetest->mock(test_flags => sub { return {always_rollback => 1, milestone => 1}; });
    stderr_like(sub { autotest::run_all }, qr/finished/, 'run_all outputs status on stderr');
    ($died, $completed) = get_tests_done;
    is($died,         0, 'start+next+start should not die when always_rollback flag is set');
    is($completed,    1, 'start+next+start should complete when always_rollback flag is set');
    is($reverts_done, 2, "Snapshots are loaded even when tests succeed");
    @sent = [];

    # # Revert mocks
    $mock_basetest->unmock('test_flags');
    $mock_autotest->unmock('load_snapshot');
    $mock_autotest->unmock('query_isotovideo');
};

my $targs = OpenQA::Test::RunArgs->new();
stderr_like(
    sub {
        autotest::loadtest("tests/run_args.pm", name => 'alt_name', run_args => $targs);
    },
    qr@scheduling alt_name tests/run_args.pm@
);
stderr_like(sub { autotest::run_all }, qr/finished alt_name tests/, 'dynamic scheduled alt_name shows up');
($died, $completed) = get_tests_done;
is($died,      0, 'run_args test should not die');
is($completed, 1, 'run_args test should complete');
@sent = [];

stderr_like(
    sub {
        autotest::loadtest("tests/run_args.pm", name => 'alt_name');
    },
    qr@scheduling alt_name tests/run_args.pm@
);
stderr_like(sub { autotest::run_all }, qr/Snapshots are not supported/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      0, 'run_args test should not die if there is no run_args');
is($completed, 0, 'run_args test should not complete if there is no run_args');
@sent = [];

eval { autotest::loadtest("tests/run_args.pm", name => 'alt_name', run_args => {foo => 'bar'}); };
like($@, qr/The run_args must be a sub-class of OpenQA::Test::RunArgs/, 'error message mentions RunArgs');

# now let's make the tests fail...but so far none is fatal. We also
# have to mock query_isotovideo so we think snapshots are supported.
# we cause the failure by mocking runtest rather than using a test
# which dies, as runtest does a whole bunch of stuff when the test
# dies that we may not want to run into here
$mock_basetest->mock(runtest => sub { die 'oh noes!'; });
my $enable_snapshots = 1;
$mock_autotest->mock(query_isotovideo => sub {
        my ($command, $arguments) = @_;
        return $enable_snapshots if $command eq 'backend_can_handle' && $arguments->{function} eq 'snapshots';
        return 1;
});

stderr_like(sub { autotest::run_all }, qr/oh noes/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      0, 'non-fatal test failure should not die');
is($completed, 1, 'non-fatal test failure should complete');
@sent = [];

# now let's add an ignore_failure test
loadtest 'ignore_failure';
stderr_like(sub { autotest::run_all }, qr/oh noes/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      0, 'unimportant test failure should not die');
is($completed, 1, 'unimportant test failure should complete');
@sent = [];

# unmock runtest, to fail in search_for_expected_serial_failures
$mock_basetest->unmock('runtest');
# mock reading of the serial output
$mock_basetest->mock(search_for_expected_serial_failures => sub {
        my ($self) = @_;
        $self->{fatal_failure} = 1;
        die "Got serial hard failure";
});

stderr_like(sub { autotest::run_all }, qr/Snapshots are supported/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      0, 'fatal serial failure test should not die');
is($completed, 0, 'fatal serial failure test should not complete');
@sent = [];

# make the serial failure non-fatal
$mock_basetest->unmock('search_for_expected_serial_failures');
$mock_basetest->mock(search_for_expected_serial_failures => sub {
        my ($self) = @_;
        $self->{fatal_failure} = 0;
        die "Got serial hard failure";
});

stderr_like(sub { autotest::run_all }, qr/Snapshots are supported/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      0, 'non-fatal serial failure test should not die');
is($completed, 1, 'non-fatal serial failure test should complete');
@sent = [];

# disable snapshots and clean last milestone from previous testrun (with had snapshots enabled)
$enable_snapshots         = 0;
$autotest::last_milestone = undef;

my $output = combined_from(sub { autotest::run_all });
like($output, qr/Snapshots are not supported/, 'snapshots actually disabled');
unlike($output, qr/Loading a VM snapshot/, 'no attempt to load VM snapshot');
($died, $completed) = get_tests_done;
is($died,      0, 'non-fatal serial failure test should not die');
is($completed, 0, 'non-fatal serial failure test should not complete by default without snapshot support');
@sent = [];

$mock_basetest->mock(test_flags => sub { return {fatal => 0}; });
$output = combined_from(sub { autotest::run_all });
like($output, qr/Snapshots are not supported/, 'snapshots actually disabled');
unlike($output, qr/Loading a VM snapshot/, 'no attempt to load VM snapshot');
($died, $completed) = get_tests_done;
is($died,      0, 'non-fatal serial failure test should not die');
is($completed, 1, 'non-fatal serial failure test should complete with {fatal => 0} and not snapshot support');
@sent = [];

# Revert mock for runtest and remove mock for search_for_expected_serial_failures
$mock_basetest->unmock('search_for_expected_serial_failures');
$mock_basetest->unmock('test_flags');
$mock_basetest->mock(runtest => sub { die "oh noes!\n"; });

# now let's add a fatal test
loadtest 'fatal';
stderr_like(sub { autotest::run_all }, qr/oh noes/, 'run_all outputs status on stderr');
($died, $completed) = get_tests_done;
is($died,      0, 'fatal test failure should not die');
is($completed, 0, 'fatal test failure should not complete');
@sent = [];


loadtest 'fatal', 'rescheduling same step later' for 1 .. 10;
my @opts = qw(script fullname category class);
is(@{$autotest::tests{'tests-fatal'}}{@opts}, @{$autotest::tests{'tests-fatal' . $_}}{@opts}, "tests-fatal$_ share same options with tests-fatal")
  && is(@{$autotest::tests{'tests-fatal' . $_}}{name}, 'fatal#' . $_)
  for 1 .. 10;

# test scheduling new modules at job runtime
subtest 'test scheduling test modules at test runtime' => sub {
    $autotest::tests_running = 0;
    @autotest::testorder     = ();
    %autotest::tests         = ();

    my %json_data;
    my $json_filename = bmwqemu::result_dir . '/test_order.json';
    my $testorder     = [
        {
            name     => 'scheduler',
            category => 'tests',
            flags    => {},
            script   => 'tests/scheduler.pm'
        },
        {
            name     => 'next',
            category => 'tests',
            flags    => {},
            script   => 'tests/next.pm'
        }
    ];

    $mock_basetest->unmock('runtest');
    $mock_bmwqemu->mock(save_json_file => sub {
            my ($data, $filename) = @_;
            $json_data{$filename} = $data;
    });

    loadtest 'scheduler';
    ok(!defined($json_data{$json_filename}),
        "loadtest shouldn't create test_order.json before tests started");

    stderr_like(sub { autotest::run_all }, qr#scheduling next tests/next\.pm#,
        'new test module gets scheduled at runtime');
    is(scalar @autotest::testorder, 2, "loadtest adds new modules at runtime");
    is_deeply($json_data{$json_filename}, $testorder,
        "loadtest updates test_order.json at test runtime");

    $mock_bmwqemu->mock(save_json_file => sub { });
};

my $sharedir = '/home/tux/.local/lib/openqa/share';
is(autotest::parse_test_path("$sharedir/tests/sle/tests/x11/firefox.pm"),        'x11');
is(autotest::parse_test_path("$sharedir/tests/sle/tests/x11/toolkits/motif.pm"), 'x11/toolkits');
is(autotest::parse_test_path("$sharedir/factory/other/sysrq.pm"),                'other');

done_testing();

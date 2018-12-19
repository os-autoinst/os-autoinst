#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Output 'stderr_like';
use Test::Fatal;
use Test::MockModule;
use File::Basename ();

BEGIN {
    unshift @INC, '..';
}

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
is(keys %autotest::tests, 3, 'three steps have been scheduled (one twice)') || diag explain %autotest::tests;
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

    autotest::run_all;
    ($died, $completed) = get_tests_done;
    is($died,         0, 'start+next+start should not die when always_rollback flag is set');
    is($completed,    1, 'start+next+start should complete when always_rollback flag is set');
    is($reverts_done, 0, "No snapshots loaded when flag is not explicitly set to true");
    $reverts_done = 0;
    @sent         = [];

    # Test that no rollback is triggered if snapshots are not supported
    $mock_basetest->mock(test_flags       => sub { return {always_rollback => 1, milestone => 1}; });
    $mock_autotest->mock(query_isotovideo => sub { return 0; });
    my $reverts_done = 0;
    $mock_autotest->mock(load_snapshot => sub { $reverts_done++; });

    autotest::run_all;
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

    autotest::run_all;
    ($died, $completed) = get_tests_done;
    is($died,         0, 'start+next+start should not die when always_rollback flag is set');
    is($completed,    1, 'start+next+start should complete when always_rollback flag is set');
    is($reverts_done, 0, "No snapshots loaded if not test with milestone flag");
    $reverts_done = 0;
    @sent         = [];

    # Test with snapshot available
    $mock_basetest->mock(test_flags => sub { return {always_rollback => 1, milestone => 1}; });
    autotest::run_all;
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
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'run_args test should not die if there is no run_args');
is($completed, 0, 'run_args test should not complete if there is no run_args');
@sent = [];

eval { autotest::loadtest("tests/run_args.pm", name => 'alt_name', run_args => {foo => 'bar'}); };
like($@, qr/The run_args must be a sub-class of OpenQA::Test::RunArgs/);

# now let's make the tests fail...but so far none is fatal. We also
# have to mock query_isotovideo so we think snapshots are supported.
# we cause the failure by mocking runtest rather than using a test
# which dies, as runtest does a whole bunch of stuff when the test
# dies that we may not want to run into here
$mock_basetest->mock(runtest          => sub { die 'oh noes!'; });
$mock_autotest->mock(query_isotovideo => sub { return 1; });

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
# Mock reading of the serial output
$mock_basetest->mock(search_for_expected_serial_failures => sub {
        my ($self) = @_;
        $self->{fatal_failure} = 1;
        die "Got serial hard failure";
});
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'fatal serial failure test should not die');
is($completed, 0, 'fatal serial failure test should not complete');
@sent = [];
$mock_basetest->unmock('search_for_expected_serial_failures');
$mock_basetest->mock(search_for_expected_serial_failures => sub {
        my ($self) = @_;
        $self->{fatal_failure} = 0;
        die "Got serial hard failure";
});
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'non-fatal serial failure test should not die');
is($completed, 1, 'non-fatal serial failure test should complete');
@sent = [];
# Revert mock for runtest and remove mock for search_for_expected_serial_failures
$mock_basetest->unmock('search_for_expected_serial_failures');
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

my $sharedir = '/home/tux/.local/lib/openqa/share';
is(autotest::parse_test_path("$sharedir/tests/sle/tests/x11/firefox.pm"),        ('firefox', 'x11'));
is(autotest::parse_test_path("$sharedir/tests/sle/tests/x11/toolkits/motif.pm"), ('motif',   'x11/toolkits'));
is(autotest::parse_test_path("$sharedir/factory/other/sysrq.pm"),                ('sysrq',   'other'));

done_testing();

# vim: set sw=4 et:

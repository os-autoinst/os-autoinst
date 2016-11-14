#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Output;
use Test::Fatal;

BEGIN {
    unshift @INC, '..';
}

require bmwqemu;

my $cmds;
use Test::MockModule;
my $mod       = new Test::MockModule('myjsonrpc');
my $fake_exit = 0;

sub fake_send_json {
    my ($to_fd, $cmd) = @_;
    push(@$cmds, $cmd);
}

sub fake_read_json {
    my ($fd) = @_;
    my $lcmd = $cmds->[-1];
    if ($lcmd->{cmd} eq 'backend_wait_serial') {
        my $str = $lcmd->{regexp};
        $str =~ s,\\d\+,$fake_exit,;
        return {ret => {matched => 1, string => $str}};
    }
    elsif ($lcmd->{cmd} eq 'backend_select_console') {
        return {ret => {activated => 0}};
    }
    elsif ($lcmd->{cmd} eq 'backend_is_serial_terminal') {
        return {ret => {yesorno => 0}};
    }
    return {};
}

$mod->mock(send_json => \&fake_send_json);
$mod->mock(read_json => \&fake_read_json);

use testapi qw(is_serial_terminal :DEFAULT);
use basetest;
*{basetest::_result_add_screenshot} = sub { my ($self, $result) = @_; };
$autotest::current_test = basetest->new();

# we have to mock out wait_screen_change for the type_string tests
# that use it, as it doesn't work with the fake send_json and read_json
my $mod2 = new Test::MockModule('testapi');

sub fake_wait_screen_change {
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
is_deeply($cmds, [
    {cmd => 'backend_type_string', max_interval => 250, text => 'hal'},
    {cmd => 'backend_type_string', max_interval => 250, text => 'lo'},
]);
$cmds = [];

type_string 'hallo', wait_screen_change => 2;
is_deeply($cmds, [
    {cmd => 'backend_type_string', max_interval => 250, text => 'ha'},
    {cmd => 'backend_type_string', max_interval => 250, text => 'll'},
    {cmd => 'backend_type_string', max_interval => 250, text => 'o'},
]);
$cmds = [];

type_string 'hallo', wait_screen_change => 3, max_interval => 10;
is_deeply($cmds, [
    {cmd => 'backend_type_string', max_interval => 10, text => 'hal'},
    {cmd => 'backend_type_string', max_interval => 10, text => 'lo'},
]);
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

is($autotest::current_test->{dents}, 0, 'no soft failures so far');
stderr_like(\&record_soft_failure, qr/record_soft_failure\(reason=undef\)/, 'soft failure recorded in log');
is($autotest::current_test->{dents}, 1, 'soft failure recorded');
stderr_like(sub { record_soft_failure('workaround for bug#1234') }, qr/record_soft_failure.*reason=.*workaround for bug#1234.*/, 'soft failure with reason');
is($autotest::current_test->{dents}, 2, 'another');
my $details = $autotest::current_test->{details}[-1];
is($details->{title}, 'Soft Failed', 'title for soft failure added');
like($details->{text}, qr/basetest-[0-9]+.*txt/, 'file for soft failure added');

require distribution;
testapi::set_distribution(distribution->new());
select_console('a-console');
is(is_serial_terminal, 0, 'Not a serial terminal');

subtest 'script_run' => sub {
    my $module = new Test::MockModule('bmwqemu');
    # just save ourselves some time during testing
    $module->mock('wait_for_one_more_screenshot', sub { sleep 0; });

    is(assert_script_run('true'), undef, 'nothing happens on success');
    $fake_exit = 1;
    like(exception { assert_script_run 'false', 42; }, qr/command.*false.*failed at/, 'with timeout option (deprecated mode)');
    like(exception { assert_script_run 'false', 0, 'my custom fail message'; }, qr/command.*false.*failed: my custom fail message at/, 'custom message on die (deprecated mode)');
    like(exception { assert_script_run('false', fail_message => 'my custom fail message'); }, qr/command.*false.*failed: my custom fail message at/, 'using named arguments');
    like(exception { assert_script_run('false', timeout => 0, fail_message => 'my custom fail message'); }, qr/command.*false.*failed: my custom fail message at/, 'using two named arguments');
    $fake_exit = 0;
    is(script_run('true'), '0', 'script_run with no check of success, returns exit code');
    $fake_exit = 1;
    is(script_run('false'), '1', 'script_run with no check of success, returns exit code');
    is(script_run('false', 0), undef, 'script_run with no check of success, returns undef when not waiting');
};

done_testing();

# vim: set sw=4 et:

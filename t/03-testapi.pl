#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 12;
use Test::Output;
use Test::Fatal;

BEGIN {
    unshift @INC, '..';
}

require bmwqemu;
require t::test_driver;

$bmwqemu::backend = t::test_driver->new;

use testapi;

my $cmd = 't::test_driver::type_string';
type_string 'hallo';
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 250, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', 4;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 4, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 250, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

type_string 'hallo', secret => 1, max_interval => 10;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 10, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

$testapi::password = 'stupid';
type_password;
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 100, text => 'stupid'}]);
$bmwqemu::backend->{cmds} = [];

type_password 'hallo';
is_deeply($bmwqemu::backend->{cmds}, [$cmd, {max_interval => 100, text => 'hallo'}]);
$bmwqemu::backend->{cmds} = [];

is($autotest::current_test->{dents}, undef, 'no soft failures so far');
stderr_like(\&record_soft_failure, qr/record_soft_failure\(reason=undef\)/, 'soft failure recorded in log');
is($autotest::current_test->{dents}, 1, 'soft failure recorded');
stderr_like(sub { record_soft_failure('workaround for bug#1234') }, qr/record_soft_failure.*reason=.*workaround for bug#1234.*/, 'soft failure with reason');
is($autotest::current_test->{dents}, 2, 'another');

subtest 'script_run' => sub {
    use autotest;
    $testapi::serialdev = 'null';
    {
        package t::test;

        sub new {
            my ($class) = @_;
            my $hash = {script => 'none'};
            return bless $hash, $class;
        }

        sub record_serialresult {
            my ($self) = @_;
        }
    }
    $autotest::current_test = t::test->new();

    use Test::MockModule;
    my $module = new Test::MockModule('bmwqemu');
    # just save ourselves some time during testing
    $module->mock('wait_for_one_more_screenshot', sub { sleep 0; });

    require distribution;
    testapi::set_distribution(distribution->new());
    is(assert_script_run('true'), undef, 'nothing happens on success');
    $bmwqemu::backend->mock_exit_code(1);
    like(exception { assert_script_run 'false', 42; }, qr/command.*false.*failed at/, 'with timeout option (deprecated mode)');
    like(exception { assert_script_run 'false', 0, 'my custom fail message'; }, qr/command.*false.*failed: my custom fail message at/, 'custom message on die (deprecated mode)');
    like(exception { assert_script_run('false', fail_message => 'my custom fail message'); }, qr/command.*false.*failed: my custom fail message at/, 'using named arguments');
    like(exception { assert_script_run('false', timeout => 0, fail_message => 'my custom fail message'); }, qr/command.*false.*failed: my custom fail message at/, 'using two named arguments');
    $bmwqemu::backend->mock_exit_code(0);
    is(script_run('true'), '0', 'script_run with no check of success, returns exit code');
    $bmwqemu::backend->mock_exit_code(1);
    is(script_run('false'), '1', 'script_run with no check of success, returns exit code');
    is(script_run('false', 0), '0', 'script_run with no check of success, returns 0 when not waiting');
};

# vim: set sw=4 et:

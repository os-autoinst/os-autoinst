#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use Test::MockModule;
use Test::Mock::Time;
use Test::Output qw(stderr_like);
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use backend::amt;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $ipc_run_mock = Test::MockModule->new('IPC::Run');

sub redefine_ipc_run_cmd ($expected_stdout = ':ReturnValue>0<') {
    $ipc_run_mock->redefine(run => sub ($args, $stdin, $stdout, $stderr) {
            $$stdin = 'stdin';
            $$stdout = $expected_stdout;
            $$stderr = 'stderr';
    });
}

$bmwqemu::vars{AMT_HOSTNAME} = 'localhost';
$bmwqemu::vars{AMT_PASSWORD} = 'password';
my $backend;
stderr_like { $backend = backend::amt->new } qr/DEPRECATED/, 'backend can be created but is deprecated';
is $backend->wsman_cmdline, 16992, 'wsman_cmdline generated';
my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
# silence some log output for cleaner tests
$bmwqemu_mock->noop('diag');
redefine_ipc_run_cmd;
ok $backend->wsman('', undef), 'can call wsman';
ok $backend->enable_solider, 'can call enable_solider';
ok $backend->configure_vnc, 'can call configure_vnc';
redefine_ipc_run_cmd(':PowerState>0<');
is $backend->get_power_state, 0, 'can call get_power_state';
is $backend->is_shutdown, '', 'can call is_shutdown';
is $backend->set_power_state('foo'), '', 'can call set_power_state';
like exception { $backend->select_next_boot('hdd') }, qr/ChangeBootOrder failed/, 'select_next_boot evaluates wsman command';
redefine_ipc_run_cmd;
my $backend_mock = Test::MockModule->new('backend::amt');
$backend_mock->redefine(is_shutdown => 1);
my $distri = Test::MockModule->new('distribution');
$testapi::distri = distribution->new;
stderr_like { $backend->do_start_vm } qr/Error connecting to VNC/, 'can call do_start_vm';
ok $backend->do_stop_vm, 'can call do_stop_vm';

done_testing;

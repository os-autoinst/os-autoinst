#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use Test::MockObject;
use Test::Mock::Time;
use Test::Output qw(stderr_like);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use distribution;
use bmwqemu;
use backend::hyperv;    # SUT

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
$bmwqemu::vars{VIRSH_HOSTNAME} = 'foobar';
$bmwqemu::vars{VIRSH_USERNAME} = 'root';
$bmwqemu::vars{VIRSH_PASSWORD} = 'password';
$bmwqemu::vars{VIRSH_VMM_FAMILY} = 'hyperv';
$bmwqemu::vars{VIRSH_GUEST} = 'barfoo';
$bmwqemu::vars{VIRSH_GUEST_PASSWORD} = 'password';
$bmwqemu::vars{HYPERV_SERVER} = 'foobar';
$bmwqemu::vars{HYPERV_SERIAL_PORT} = '223';
$testapi::distri = distribution->new();

my $chan_object = Test::MockObject->new();
$chan_object->set_true(qw/channel eof send_eof exit_status/)->set_false('exec');
my $ssh_object = Test::MockObject->new();
$ssh_object->set_true(qw/die_with_error error blocking/);
$ssh_object->set_always(channel => $chan_object);
my $run_ssh_cmd_mock = Test::MockModule->new('backend::baseclass');
$run_ssh_cmd_mock->redefine(new_ssh_connection => sub ($self, %args) { return $ssh_object });
$run_ssh_cmd_mock->redefine(start_ssh_serial => sub { return ($ssh_object, $chan_object) });
$run_ssh_cmd_mock->redefine(run_ssh_cmd => 0);

$bmwqemu::vars{NO_DEPRECATE_BACKEND_SVIRT_HYPERV} = 1;
my $backend;
stderr_like { $backend = backend::hyperv->new } qr/DEPRECATED/, 'hyperv (temporarily) marked deprecated until it is stand-alone from svirt';
my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
# silence some log output for cleaner tests
$bmwqemu_mock->noop('diag');
$bmwqemu_mock->noop('log_call');
ok $backend->do_start_vm, 'can start vm';
is $backend->can_handle({function => 'snapshots'})->{ret}, 1, 'can handle snapshots';
is $backend->save_snapshot({name => 'Snap1'}), undef, 'can save snapshot - always return undef';
is $backend->load_snapshot({name => 'Snap1'}), '', 'can load snapshot';
stderr_like { $backend->start_serial_grab('svirt') } qr/unable to grab serial console/, 'start serial grab aborts';
ok $backend->do_stop_vm, 'can stop vm';
is $backend->is_shutdown, 0, 'can call is_shutdown';

done_testing;

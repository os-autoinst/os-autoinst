#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use Test::MockModule;
use Test::MockObject;
use Test::Mock::Time;
use Test::Output qw(stderr_like);
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use backend::svirt;
use distribution;

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
chdir $dir;
my $cleanup = scope_guard sub { chdir $Bin; undef $dir };

my $ssh_object = Test::MockObject->new();
$ssh_object->set_true(qw/disconnect scp_get blocking/);
$ssh_object->set_always('error', 'Mock SSH Error');

my $chan_object = Test::MockObject->new();
$chan_object->set_true(qw/exec/);

my $run_ssh_cmd_mock = Test::MockModule->new('backend::baseclass');
$run_ssh_cmd_mock->redefine(new_ssh_connection => sub ($self, %args) { return $ssh_object });
$run_ssh_cmd_mock->redefine(start_ssh_serial => sub { return ($ssh_object, $chan_object) });

sub redefine_ssh ($excepted = 0) {
    $run_ssh_cmd_mock->redefine(run_ssh_cmd => sub ($self, $cmd, %args) {
            return ref($excepted) eq 'ARRAY' ? @$excepted : $excepted;
    });
}

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
$bmwqemu::vars{VIRSH_HOSTNAME} = 'foobar';
$bmwqemu::vars{VIRSH_USERNAME} = 'root';
$bmwqemu::vars{VIRSH_PASSWORD} = 'password';
$bmwqemu::vars{JOBTOKEN} = "JobToken";

my $distri = $testapi::distri = distribution->new();

subtest 'Generic svirt backend' => sub {
    my @diag_log;
    my $backend = backend::svirt->new;
    my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
    # silence some log output for cleaner tests
    $bmwqemu_mock->noop('diag');
    $bmwqemu_mock->noop('log_call');
    redefine_ssh;
    $backend->{need_delete_log} = 1;
    ok $backend->do_start_vm, 'can start vm';
    # not kvm/hyperv or vmware
    is $backend->can_handle({function => 'snapshots'}), undef, 'can not handle snapshots';
    $bmwqemu_mock->mock(diag => sub { push @diag_log, @_ });
    is $backend->save_snapshot({name => "Snap1"}), undef, 'can save snapshot - always return undef or die';
    like "@diag_log", qr/SAVE VM/, "vm snapshot logged";
    $bmwqemu_mock->noop('diag');
    is $backend->load_snapshot({name => "Snap1"}), '', 'can load snapshot - returns empty string';
    ok $backend->start_serial_grab('svirt'), 'can start serial grab';
    ok $backend->do_stop_vm, 'can stop vm';
    redefine_ssh "Power OFF";
    is $backend->is_shutdown, 'Power OFF', 'can call is_shutdown';
};

subtest 'VMWARE backend' => sub {
    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware';
    $bmwqemu::vars{VMWARE_HOST} = "foobar";
    $bmwqemu::vars{VMWARE_SERIAL_PORT} = "222";

    my $backend = backend::svirt->new;
    my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
    # silence some log output for cleaner tests
    $bmwqemu_mock->noop('diag');
    $bmwqemu_mock->noop('log_call');
    redefine_ssh;
    $backend->{need_delete_log} = 1;
    ok $backend->do_start_vm, 'can start vm';
    is $backend->can_handle({function => 'snapshots'})->{ret}, 1, 'can handle snapshots';
    is $backend->save_snapshot({name => "Snap1"}), undef, 'can save snapshot - always returns undef or die';
    is $backend->load_snapshot({name => "Snap1"}), 'vmware_fixup', 'can load snapshot - on wmware returns string "vmware_fixup"';
    ok $backend->start_serial_grab('svirt'), 'can start serial grab';
    ok $backend->do_stop_vm, 'can stop vm';
    redefine_ssh "Power OFF";
    is $backend->is_shutdown, 'Power OFF', 'can call is_shutdown';
};

subtest 'HyperV backend' => sub {
    my @warn_log;
    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'hyperv';
    $bmwqemu::vars{VIRSH_GUEST} = 'barfoo';
    $bmwqemu::vars{VIRSH_GUEST_PASSWORD} = 'password';
    $bmwqemu::vars{HYPERV_SERVER} = 'foobar';
    $bmwqemu::vars{HYPERV_SERIAL_PORT} = '223';
    my $backend = backend::svirt->new;
    my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
    # silence some log output for cleaner tests
    $bmwqemu_mock->noop('diag');
    $bmwqemu_mock->noop('log_call');
    redefine_ssh;
    ok $backend->do_start_vm, 'can start vm';
    is $backend->can_handle({function => 'snapshots'})->{ret}, 1, 'can handle snapshots';
    is $backend->save_snapshot({name => "Snap1"}), undef, 'can save snapshot - alswais return undef';
    redefine_ssh(1);
    throws_ok { $backend->load_snapshot({name => "Snap1"}) } qr/freerdp/, 'theows exception during load_snapshot - freerdp';
    redefine_ssh;
    $chan_object->set_false('exec');
    $bmwqemu_mock->mock(fctwarn => sub { push @warn_log, @_ });
    ok $backend->start_serial_grab('svirt'), 'can start serial grab';
    like "@warn_log", qr/Mock SSH Error/, 'capture SSH Error';
    ok $backend->do_stop_vm, 'can stop vm';
    redefine_ssh "Power OFF";
    is $backend->is_shutdown, 'Power OFF', 'can call is_shutdown';
};

done_testing;

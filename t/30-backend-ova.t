#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockModule;
use Test::MockObject;
use Test::Mock::Time;
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use backend::ova;
use consoles::sshVirtshOVA;
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

my @run_cmds;
$run_ssh_cmd_mock->redefine(run_ssh_cmd => sub ($self, $cmd, %args) {
        push @run_cmds, $cmd;
        return 0;
});

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
$bmwqemu::vars{VIRSH_HOSTNAME} = 'foobar';
$bmwqemu::vars{VIRSH_USERNAME} = 'root';
$bmwqemu::vars{VIRSH_PASSWORD} = 'password';
$bmwqemu::vars{JOBTOKEN} = 'JobToken';

my $bmwqemu_mock = Test::MockModule->new('bmwqemu');
$bmwqemu_mock->noop('diag');
$bmwqemu_mock->noop('log_call');

my $distri = $testapi::distri = distribution->new();

subtest 'OVA backend initialization' => sub {
    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware';
    my $backend = backend::ova->new;
    ok $backend, 'can instantiate backend::ova';

    $backend->{need_delete_log} = 1;
    ok $backend->do_start_vm, 'can start vm in backend::ova';

    my $console = $distri->{consoles}->{svirt};
    ok $console, 'svirt console exists';
    is $console->{class}, 'consoles::sshVirtshOVA', 'svirt console has correct class consoles::sshVirtshOVA';
};

subtest 'OVA console define_and_start' => sub {
    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware';
    my $backend = backend::ova->new;
    $backend->{need_delete_log} = 1;
    $backend->do_start_vm;
    my $console = $distri->{consoles}->{svirt};

    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware';
    $bmwqemu::vars{OVA} = '/path/to/test.ova';
    $bmwqemu::vars{VMWARE_HOST} = 'esxi.host';
    $bmwqemu::vars{VMWARE_USERNAME} = 'user';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'pass';
    $bmwqemu::vars{VMWARE_DATASTORE} = 'ds1';
    $bmwqemu::vars{VMWARE_NETWORK} = 'target_net';
    $bmwqemu::vars{VMWARE_SERIAL_PORT} = '1234';
    $bmwqemu::vars{OVFTOOL_ARGS} = '--diskMode=thin';

    my $ssh_virtsh_mock = Test::MockModule->new('consoles::sshVirtsh');
    $ssh_virtsh_mock->redefine(get_cmd_output => sub ($self, $cmd) {
            return '<domain id="123"></domain>';
    });

    @run_cmds = ();

    $console->_init_ssh($console->{args});
    $console->define_and_start;

    my ($ovftool_cmd) = grep { /ovftool/ } @run_cmds;
    ok $ovftool_cmd, 'ovftool command is generated and executed';
    like $ovftool_cmd, qr/ovftool/, 'command binary is ovftool';
    like $ovftool_cmd, qr/--acceptAllEulas/, 'EULA is accepted via --acceptAllEulas';
    like $ovftool_cmd, qr/--noSSLVerify/, 'SSL verification is bypassed via --noSSLVerify';
    like $ovftool_cmd, qr/--overwrite/, 'existing VM is overwritten via --overwrite';
    like $ovftool_cmd, qr/--powerOffTarget/, 'target VM is powered off if running via --powerOffTarget';
    like $ovftool_cmd, qr/--name=openQA-SUT-1/, 'VM name is set via --name=openQA-SUT-1';
    like $ovftool_cmd, qr/--datastore=ds1/, 'target datastore is set via --datastore=ds1';
    like $ovftool_cmd, qr/'--net:VM Network=target_net'/, 'network is mapped via --net:VM Network=target_net';
    like $ovftool_cmd, qr/--diskMode=thin/, 'additional arguments from OVFTOOL_ARGS are appended';
    like $ovftool_cmd, qr/'\/path\/to\/test\.ova'/, 'correct escaped OVA path is passed';
    like $ovftool_cmd, qr/'vi:\/\/user:pass\@esxi\.host'/, 'target URL is constructed with credentials and host';
};

subtest 'OVA console define_and_start with extra options' => sub {
    my $backend = backend::ova->new;
    $backend->{need_delete_log} = 1;
    $backend->do_start_vm;
    my $console = $distri->{consoles}->{svirt};
    $bmwqemu::vars{VIRSH_VMM_FAMILY} = 'vmware';
    $bmwqemu::vars{OVA} = '/path/to/test.ova';
    $bmwqemu::vars{VMWARE_HOST} = 'esxi.host';
    $bmwqemu::vars{VMWARE_USERNAME} = 'user';
    $bmwqemu::vars{VMWARE_PASSWORD} = 'pass';
    $bmwqemu::vars{VMWARE_DATASTORE} = 'ds1';
    $bmwqemu::vars{VMWARE_VM_HWVERSION} = '19';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'combustion';
    $bmwqemu::vars{GUESTINFO_COMBUSTION} = 'combustion.script';
    my $ssh_virtsh_mock = Test::MockModule->new('consoles::sshVirtsh');
    $ssh_virtsh_mock->redefine(get_cmd_output => sub ($self, $cmd) {
            return '<domain id="123"></domain>';
    });
    $ssh_virtsh_mock->redefine(_encode_config => sub ($self, $conf, $var) {
            return 'encoded_config';
    });
    @run_cmds = ();
    $console->_init_ssh($console->{args});
    $console->define_and_start;
    my ($sed_cmd) = grep { /virtualHW.version = "19"/ } @run_cmds;
    ok $sed_cmd, 'virtualHW.version is set when VMWARE_VM_HWVERSION is specified';
    my ($combustion_cmd) = grep { /guestinfo.combustion.script = "encoded_config"/ } @run_cmds;
    ok $combustion_cmd, 'guestinfo.combustion.script set correctly for combustion provisioning';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'ignition';
    $bmwqemu::vars{GUESTINFO_IGNITION} = 'ignition.config';
    @run_cmds = ();
    $console->define_and_start;
    my ($ignition_cmd) = grep { /guestinfo.ignition.config.data = "encoded_config"/ } @run_cmds;
    ok $ignition_cmd, 'guestinfo.ignition.config.data set correctly for ignition provisioning';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'cloud-init';
    $bmwqemu::vars{GUESTINFO_CLOUD_INIT} = 'user-data,meta-data';
    @run_cmds = ();
    $console->define_and_start;
    my ($cloud_init_cmd) = grep { /guestinfo.userdata = "encoded_config"/ } @run_cmds;
    ok $cloud_init_cmd, 'guestinfo.userdata set correctly for cloud-init provisioning';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'invalid';
    @run_cmds = ();
    throws_ok { $console->define_and_start } qr/Unknown provisioning option/, 'throws error when invalid GUESTINFO_CONFIG is provided';
    $bmwqemu::vars{GUESTINFO_CONFIG} = 'cloud-init';
    delete $bmwqemu::vars{GUESTINFO_CLOUD_INIT};
    @run_cmds = ();
    throws_ok { $console->define_and_start } qr/GUESTINFO_CLOUD_INIT is unset/, 'throws error when GUESTINFO_CLOUD_INIT is unset for cloud-init provisioning';
};
done_testing;

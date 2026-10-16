#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;
use Test::MockObject;
use Test::MockModule;
use Test::Warnings ':report_warnings';
use Test::Output;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::sshIucvconn;    # SUT

my $testapi_console = 'sshIucvconn';
my $args = {hostname => 'testhost', password => 'testpass'};
my $exec_flag = 1;
$bmwqemu::vars{ZVM_GUEST} = 'guest.what';

my (@ssh_conn_args, @serial_args);
my $backend_mock = Test::MockObject->new();
$backend_mock->mock('new_ssh_connection', sub ($self, %args) {
        push @ssh_conn_args, \%args;
        my $ttyconn_mock = Test::MockObject->new;
        $ttyconn_mock->mock('channel', sub {
                return Test::MockObject->new->set_true('blocking', 'pty')->set_always(exec => $exec_flag);
        });
        return $ttyconn_mock->set_false('error');
});
$backend_mock->mock('start_ssh_serial', sub ($self, %args) {
        push @serial_args, \%args;
        my $ssh_mock = Test::MockObject->new;
        $ssh_mock->set_true('blocking')->set_always(error => 'unknown SSH error');
        my $serialchan_mock = Test::MockObject->new;
        $serialchan_mock->set_always(exec => $exec_flag);
        return ($ssh_mock, $serialchan_mock);
});
$backend_mock->set_true('stop_ssh_serial');

my $sshIucvconn_mock = Test::MockModule->new("consoles::$testapi_console");
$sshIucvconn_mock->redefine(backend => $backend_mock);

subtest 'connect_remote test' => sub {
    my $c = consoles::sshIucvconn->new($testapi_console, $args);
    my $captured_output = stderr_from { $c->connect_remote($args) };
    like $captured_output, qr/g serial console for guest/, 'Captured expected debug log';
    ok $c->kill_ssh(), 'kill_ssh executed successfully';
};

subtest 'connect_remote uses configured SUT port for all SSH connections' => sub {
    my @cases = (
        {desc => 'custom port from console args', args => {%$args, port => 10022}, port => 10022},
        {desc => 'port defaults to 22 without SUT_SSH_PORT', args => {%$args}, port => 22},
        {desc => 'SUT_SSH_PORT used when no port arg', args => {%$args}, vars => 10022, port => 10022},
        {desc => 'args port wins over SUT_SSH_PORT', args => {%$args, port => 2222}, vars => 10022, port => 2222},
    );
    for my $case (@cases) {
        @ssh_conn_args = @serial_args = ();
        local $bmwqemu::vars{SUT_SSH_PORT} = $case->{vars};
        my $c = consoles::sshIucvconn->new($testapi_console, $case->{args});
        stderr_like { $c->connect_remote($case->{args}) } qr/serial console for guest/, "connect_remote: $case->{desc}";
        is $ssh_conn_args[0]{port}, $case->{port}, "agetty SSH connection: $case->{desc}";
        is $serial_args[0]{port}, $case->{port}, "iucvconn SSH connection: $case->{desc}";
    }
};

subtest 'connect_remote test warning output' => sub {
    $exec_flag = 0;
    my $c = consoles::sshIucvconn->new($testapi_console, $args);
    my $captured_output = stderr_from { $c->connect_remote($args) };
    like $captured_output, qr/Unable to execute "smart_agetty hvc0" at this point/, 'Captured expected error when smart_agetty hvc0 fails';
    like $captured_output, qr/ssh iucvconn: unable to grab serial console at this point/, 'Captured ssh iucvconn error';
};

done_testing();

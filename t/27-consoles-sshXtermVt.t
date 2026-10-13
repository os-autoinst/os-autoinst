#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -signatures;
use Test::Most;
use Test::Warnings qw(:report_warnings);
use Test::MockObject;
use Test::MockModule;
use Test::Output qw(stderr_from);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use POSIX qw(_exit);
use consoles::sshXtermVt;
use OpenQA::Test::TimeLimit '10';

$bmwqemu::vars{SSH_XTERM_WAIT_SUT_ALIVE_TIMEOUT} = 1;

plan skip_all => 'No network support found' unless getprotobyname 'tcp';

my $vnc_base_mock = Test::MockModule->new('consoles::vnc_base');
my $vnc_mock = Test::MockObject->new->set_true('check_vnc_stalls');
$vnc_base_mock->redefine(connect_remote => $vnc_mock);
$bmwqemu::topdir = "$Bin/..";
my $local_xvnc_mock = Test::MockModule->new('consoles::localXvnc');
$local_xvnc_mock->redefine(start_xvnc => sub {
        _exit(0);    # uncoverable statement
});

my $args = {hostname => 'testhost', password => 'testpass', serial => '/dev/ttyS0'};

my $backend_mock = Test::MockObject->new();
$backend_mock->mock(
    'start_ssh_serial',
    sub {
        return (
            Test::MockObject->new->set_always('blocking', 1),
            Test::MockObject->new->mock('exec', sub { 1 })
        );
    }
);
$backend_mock->set_true('stop_ssh_serial');
my $c = consoles::sshXtermVt->new('sut', $args);
$c->{backend} = $backend_mock;
my $captured_output = stderr_from { $c->activate() };
like $captured_output, qr/Wait for SSH on host testhost/, 'Captured expected debug log';
ok $c->kill_ssh(), 'kill_ssh executed successfully';

subtest 'activate resolves SSH port from args and SUT_SSH_PORT' => sub {
    my $sshxterm_mock = Test::MockModule->new('consoles::sshXtermVt');
    my (@ssh_command_args, @wait_args);
    $sshxterm_mock->redefine(sshCommand => sub ($self, @args) { @ssh_command_args = @args; 'ssh-cmd' });
    $sshxterm_mock->redefine(wait_for_ssh_port => sub ($self, @args) { @wait_args = @args; 1 });
    my @cases = (
        {desc => 'SUT_SSH_PORT used when no args port', args => {hostname => 'testhost'}, port => 10022},
        {desc => 'args port wins over SUT_SSH_PORT', args => {hostname => 'testhost', port => 2222}, port => 2222},
    );
    for my $case (@cases) {
        local $bmwqemu::vars{SUT_SSH_PORT} = 10022;
        @ssh_command_args = @wait_args = ();
        stderr_from { consoles::sshXtermVt->new('sut', $case->{args})->activate };
        my %wait_opts = @wait_args[1 .. $#wait_args];
        is $ssh_command_args[2], $case->{port}, "SSH command: $case->{desc}";
        is $wait_opts{port}, $case->{port}, "SSH readiness check: $case->{desc}";
    }
};

done_testing();

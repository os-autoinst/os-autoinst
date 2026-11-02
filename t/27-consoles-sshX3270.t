#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -signatures;
use Test::Most;
use Test::Mock::Time;
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(stdout_from);
use Test::Warnings qw(:all :report_warnings);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use bmwqemu;
use consoles::sshX3270;
use testapi;

subtest 'ssh_port resolution from console args and SUT_SSH_PORT' => sub {
    my $c = consoles::sshX3270->new('sut', {});
    is $c->ssh_port({}), 22, 'ssh_port defaults to 22 when neither args nor SUT_SSH_PORT set';
    local $bmwqemu::vars{SUT_SSH_PORT} = 10022;
    is $c->ssh_port({}), 10022, 'ssh_port falls back to SUT_SSH_PORT';
    is $c->ssh_port({port => 2222}), 2222, 'explicit port in console args overrides SUT_SSH_PORT';
};

subtest 'activate connects via s3270 and supplies credentials after prompt' => sub {
    local $bmwqemu::vars{PARMFILE} = {Hostname => 'testhost'};
    local $testapi::password = 'secret';

    my @sent;
    my $attempts = 0;
    my $s3270_mock = Test::MockObject->new;
    $s3270_mock->mock(send_3270 => sub ($self, $cmd = '', %args) {
            push @sent, $cmd;
            if ($cmd eq 'Snap(Ascii)') {
                $attempts++;
                return {command_output => ['Connecting to testhost...']} if $attempts == 1;
                return {command_output => ['Password: ']};
            }
            return {command_status => 'ok'};
    });

    my $sshx3270_mock = Test::MockModule->new('consoles::sshX3270', no_strict => 1);
    $sshx3270_mock->mock(new_3270_console => sub ($self, $args) { return {console => $s3270_mock} });

    my $c = consoles::sshX3270->new('sut', {port => 10022});
    $c->{backend} = {consoles => {worker => {DISPLAY => ':1'}}};

    my $output = stdout_from { $c->activate };
    like $output, qr/Connecting to testhost/, 'activate logs command output during password prompt search';
    like $sent[0], qr/Connect\("-e TERM=vt100 ssh .*-p 10022 root\@testhost; read"\)/, 's3270 connect command contains configured port and target';
    is $sent[1], 'Snap', 'snap requested before polling screen content';
    is $sent[2], 'Snap(Ascii)', 'ascii snap queried for initial password prompt check';
    is $sent[3], 'Snap', 'snap requested before second poll';
    is $sent[4], 'Snap(Ascii)', 'ascii snap queried for second password prompt check';
    is $sent[5], 'String("secret")', 'password string sent to terminal after prompt detected';
    is $sent[6], 'ENTER', 'enter key sent after password';
};

subtest 'activate dies when password prompt is not seen within timeout' => sub {
    local $bmwqemu::vars{PARMFILE} = {Hostname => 'testhost'};
    local $testapi::password = 'secret';

    my $s3270_mock = Test::MockObject->new;
    $s3270_mock->mock(send_3270 => sub ($self, $cmd = '', %args) {
            return {command_output => ['Connecting...']} if $cmd eq 'Snap(Ascii)';
            return {command_status => 'ok'};
    });

    my $sshx3270_mock = Test::MockModule->new('consoles::sshX3270', no_strict => 1);
    $sshx3270_mock->mock(new_3270_console => sub ($self, $args) { return {console => $s3270_mock} });

    my $c = consoles::sshX3270->new('sut', {});
    $c->{backend} = {consoles => {worker => {DISPLAY => ':1'}}};

    throws_ok {
        stdout_from { $c->activate };
    } qr/ssh password prompt timeout/, 'activate aborts with timeout when password prompt never appears';
};

done_testing;

#!/usr/bin/perl
# Copyright 2019 SUSE LLC

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings ':report_warnings';
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::ssh_screen;
use consoles::serial_screen;
use bmwqemu;
use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';

my $screen = consoles::ssh_screen->new(ssh_connection => 'My_Con', ssh_channel => 'My_Chan');
is($screen->{fd_read}, 'My_Chan', 'SSH channel is used for reading');
is($screen->{fd_write}, 'My_Chan', 'SSH channel is used for writing');

subtest 'Correct message when type_string timeouts' => sub {
    my $mock_screenconsole = Test::MockModule->new('consoles::serial_screen');
    $mock_screenconsole->mock('elapsed', sub { 1000 });
    my $mock_connection = Test::MockObject->new();
    my $mock_channel = Test::MockObject->new();
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    my $sshscreen = consoles::ssh_screen->new(ssh_connection => $mock_connection, ssh_channel => $mock_channel);
    throws_ok { $sshscreen->type_string({text => 'This should timeout'}) } qr/consoles::ssh_screen::type_string: Timed out after 1000 seconds/, "sub dies with correct error message and display the correct caller";
};

subtest 'test old net ssh2 error handling' => sub {
    my $mock_screenconsole = Test::MockModule->new('consoles::serial_screen');
    my $mock_connection = Test::MockObject->new();
    my $mock_write_attempts = 0;
    my $mock_channel = Test::MockObject->new();
    $mock_channel->mock('write', sub {
            $mock_write_attempts++;
            return -37 if $mock_write_attempts <= 3;    # Return EAGAIN a few times
            return length($_[1]);    # Then succeed
    });

    my $sshscreen = consoles::ssh_screen->new(ssh_connection => $mock_connection, ssh_channel => $mock_channel);
    lives_ok(
        sub { $sshscreen->type_string({text => 'test'}) },
        'Should continue after EAGAIN errors'
    );
};

done_testing;

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

my $screen = consoles::ssh_screen->new(ssh_connection => 'My_Con', ssh_channel => 'My_Chan');
is($screen->{fd_read}, 'My_Chan', 'SSH channel is used for reading');
is($screen->{fd_write}, 'My_Chan', 'SSH channel is used for writing');

subtest 'Correct message when type_string timeouts' => sub {
    my $mock_screenconsole = Test::MockModule->new('consoles::serial_screen');
    $mock_screenconsole->mock('elapsed', sub { 1000 });
    my $mock_ssh = Test::MockObject->new();
    my $mock_channel = Test::MockObject->new();
    my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
    $mock_bmwqemu->noop('log_call');
    my $sshscreen = consoles::ssh_screen->new(ssh_connection => $mock_ssh, ssh_channel => $mock_channel);
    throws_ok { $sshscreen->type_string({text => 'This should timeout'}) } qr/consoles::ssh_screen::type_string: Timed out after 1000 seconds/, "sub dies with correct error message and display the correct caller";
};

done_testing;

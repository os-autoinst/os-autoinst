#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::MockObject;
use Test::Output qw(stderr_like);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::sshVirtshSUT;

my $c = consoles::sshVirtshSUT->new('sut', {});
is $c->screen, undef, 'no screen defined';
is $c->is_serial_terminal, 1, 'is a serial terminal';
my $mock_ssh = Test::MockObject->new()->set_true('disconnect');
$c->{backend} = Test::MockObject->new()->set_list(open_serial_console_via_ssh => ($mock_ssh, 'chan'));
stderr_like { $c->activate } qr/Activate console/, 'activate can be called';
is $c->disable, undef, 'disable can be called';
ok $mock_ssh->called('disconnect'), 'disable disconnected ssh';

done_testing;

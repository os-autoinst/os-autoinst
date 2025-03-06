#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';

use FindBin '$Bin';
use lib "$FindBin::Bin/lib", "$Bin/../external/os-autoinst-common/lib";

use OpenQA::Test::TimeLimit '5';
use Net::DBus;
use Test::MockObject;

#my $mock_service = Test::MockObject->new();
#my $mock_dbus = Test::MockObject->new();
my $dbus = Net::DBus->session;
#my $mock_service = $dbus->export_service("org.opensuse.os_autoinst.switch");
my $mock_service = Net::DBus::Service->new();

$mock_dbus->set_isa('Net::DBus');
$mock_service->set_isa('Net::DBus::Service');
# Net::DBus::Service
$mock_dbus->mock('export_service', sub { return $mock_service });


require "$FindBin::Bin/../script/os-autoinst-openvswitch";

subtest 'main package' => sub {
    my $result = main::main();
    is $result, 1, 'Result of main::main';
};

subtest 'ovs package' => sub {
    my $switch = OVS->new($mock_service);
    isa_ok($switch, 'OVS', 'A new OVS instance is created');
};

done_testing;

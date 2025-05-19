#!/usr/bin/env perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings ':report_warnings';
use Test::MockObject;
use Test::MockModule qw(strict);
use Test::Mock::Time;
use Test::Output qw(combined_like stderr_like);
use FindBin '$Bin';

use lib "$FindBin::Bin/lib", "$Bin/../external/os-autoinst-common/lib";

use OpenQA::Test::TimeLimit '5';
use Net::DBus;
use Net::DBus::Reactor;

my $mock_dbus = Test::MockObject->new();
$mock_dbus->set_isa('Net::DBus');
$mock_dbus->mock(system => $mock_dbus);
$mock_dbus->mock(session => $mock_dbus);

my $mock_service = Test::MockObject->new();
$mock_service->set_isa('Net::DBus::Service');

$mock_dbus->mock(export_service => sub { $mock_service });

my $mock_reactor = Test::MockModule->new('Net::DBus::Reactor');
$mock_reactor->redefine(run => undef);

require "$FindBin::Bin/../script/os-autoinst-openvswitch";

subtest 'Main package' => sub {
    my $mock_main = Test::MockModule->new('main');
    $mock_main->redefine(run_dbus => 1);
    my $result = main::main();
    is($result, 1, 'main::main() should return 1');
};

subtest 'OVS package' => sub {
    my $mock_dbus_object = Test::MockModule->new('Net::DBus::Object');
    $mock_dbus_object->redefine('new', {});
    my $mock_main = Test::MockModule->new('OVS', no_auto => 1);
    my $wait_for_bridge_called = 0;
    $mock_main->redefine(_wait_for_bridge => sub { $wait_for_bridge_called++ });
    $mock_main->redefine(_bridge_conf => "\tlink/ether 01:23:45:67:89:ab brd ff:ff:ff:ff:ff:ff\n\tinet 10.0.2.2/15 brd 10.1.255.255 scope global br0");
    $mock_main->redefine(_add_flow => undef);
    my $result = main::run_dbus($mock_dbus);
    is $result, undef, 'run_dbus() should return 1';
    is $wait_for_bridge_called, 1, 'wait_for_bridge was called';

    subtest 'can call _ovs_check' => sub {
        $mock_main->redefine(_check_bridge => 'br1');
        is OVS::_ovs_check('tap0', 0, 'br1'), 0, 'success';
        ok OVS::_ovs_check('tap0', 0, 'br0'), 'wrong bridge';
        ok OVS::_ovs_check('something', 0, 'br0'), 'invalid tap name';
        ok OVS::_ovs_check('tap0', 'something', 'br0'), 'invalid vlan format';
    };

    is((OVS::_cmd('true'))[0], 0, 'can call _cmd');

    $mock_main->redefine(_ovs_version => '(Open vSwitch) 1.1.1');
    is OVS::check_min_ovs_version('1.1.1'), 1, 'can call check_min_ovs_version';

    my $ovs = OVS->new($mock_service);
    subtest 'can call set_vlan' => sub {
        $mock_main->redefine(_ovs_version => '(Open vSwitch) 2.8.1');
        stderr_like {
            ok $ovs->set_vlan('tap0', 1), 'tap0 is not in br0';
        } qr/'tap0'/, 'log output for missing tap';
        $mock_main->redefine(_ovs_check => sub { return (0, 1) });
        $mock_main->redefine(_cmd => sub { return (0, '', '') });
        $mock_main->redefine(_set_ip => 0);
        is(($ovs->set_vlan('tap0', 1))[0], 0, 'can call set_vlan');
    };

    $mock_main->redefine(_ovs_check => sub { return (1, 'error') });
    combined_like { is(($ovs->unset_vlan('tap0', 1))[0], 1, 'unset_vlan handles error'); } qr/error/, 'no unexpected log output from resultset';
    $mock_main->redefine(_ovs_check => sub { return (0, 'error') });
    $mock_main->redefine(_cmd => sub { return (0, '', '') });
    is(($ovs->unset_vlan('tap0', 1))[0], 0, 'can call unset_vlan');

    $mock_main->redefine(_ovs_show => 1);
    is(($ovs->show())[0], 1, 'can call show');
};

done_testing();

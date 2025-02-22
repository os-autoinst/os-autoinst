#!/usr/bin/perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Net::DBus::Exporter 'org.opensuse.os_autoinst.switch';

# use FindBin '$Bin';
# require "$Bin/../script/os-autoinst-openvswitch";

# use Test::MockModule;
# my $ovs_mock = Test::MockModule->new('OVS');
# $ovs_mock->mock('init_switch', sub {
#         print "init_switch: Skipping bridge setup";
# });

# {
#     package OVS;
#     use FindBin '$Bin';
#     *OVS::init_switch = sub {
#         print "Mocked init_switch: Skipping bridge setup.\n";
#     };
#     do "$Bin/../script/os-autoinst-openvswitch" or die "Couldn't load script: $@";
# }

subtest 'usage should not die when Pod::Usage is declared' => sub {
    my $bus = Net::DBus->session;
    my $service = $bus->export_service("org.opensuse.os_autoinst.switch");
    my $object = OVS->new($service);
    eval { usage(1) };
    my $error = $@;

    ok($error, 'Function died as expected');
    like($error, qr/cannot display help/, 'Error message matches expected text');
};

done_testing();

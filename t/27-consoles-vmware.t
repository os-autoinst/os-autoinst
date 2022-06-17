#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings;
use Mojo::Base -strict, -signatures;
use utf8;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

use consoles::VMWare;

# configure test instance
my $vmware = consoles::VMWare->new;
my $instance_url = $ENV{OS_AUTOINST_TEST_AGAINST_REAL_VMWARE_INSTANCE};
unless ($instance_url) {
    plan skip_all => 'Set OS_AUTOINST_TEST_AGAINST_REAL_VMWARE_INSTANCE to run this test.';
    exit(0);
}
$vmware->configure_from_url($instance_url);
note 'host: ' . $vmware->host // '?';
note 'username: ' . $vmware->username // '?';
note 'password: ' . $vmware->password // '?';
note 'instance: ' . $vmware->vm_id // '?';

# request wss URL and session cookie
my ($wss_url, $session) = $vmware->get_vmware_wss_url;
like $wss_url, qr{wss://.+/ticket/.+}, 'wss URL returned for VMWare host';
like $session, qr{vmware_soap_session=.+}, 'session cookie returned';
note "wss url: $wss_url\n";
note "session: $session\n";

# spawn test instance of dewebsockify for manually testing with vncviewer
if (my $port = $ENV{OS_AUTOINST_DEWEBSOCKIFY_PORT}) {
    system "'$Bin/../dewebsockify' --listenport '$port' --websocketurl '$wss_url' --cookie 'vmware_client=VMware; $session'";
}

done_testing;

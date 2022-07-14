#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Test::Warnings;
use Mojo::Base -strict, -signatures;
use utf8;

# disable time limit when testing against real VMWare instance
BEGIN {
    $ENV{OPENQA_TEST_TIMEOUT_DISABLE} = 1 if $ENV{OS_AUTOINST_TEST_AGAINST_REAL_VMWARE_INSTANCE};
}

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';

use Test::Exception;
use Test::MockObject;
use Test::MockModule;
use Test::Output qw(combined_like);
use Mojo::Transaction::HTTP;
use Mojo::Message::Request;
use Mojo::Message::Response;

use consoles::VMWare;

$bmwqemu::scriptdir = "$Bin/..";

sub mk_res ($code, @text) { map { Mojo::Message::Response->new->code($code)->body($_) } @text }

subtest 'test configuration with fake URL' => sub {
    my $vmware_mock = Test::MockModule->new('consoles::VMWare');
    my (@get_vmware_wss_url_args, @dewebsockify_args);
    $vmware_mock->redefine(get_vmware_wss_url => sub ($self) { ('wss://foo', 'session') });
    $vmware_mock->redefine(_start_dewebsockify_process => sub ($self, @args) { @dewebsockify_args = @args });

    my $fake_vnc = Test::MockObject->new;
    $fake_vnc->set_always(vmware_vnc_over_ws_url => undef);
    is consoles::VMWare::setup_for_vnc_console($fake_vnc), undef, 'noop if URL not set';

    $fake_vnc->set_always(vmware_vnc_over_ws_url => 'https://root:secret%23@foo.bar');
    $fake_vnc->set_always(port => 12345);
    $fake_vnc->set_true(qw(hostname description));
    $fake_vnc->clear;

    my $vmware;
    combined_like { $vmware = consoles::VMWare::setup_for_vnc_console($fake_vnc) }
    qr{Establishing VNC connection over WebSockets via https://foo\.bar}, 'log message present without secrets';
    ok $vmware, 'VMWare "console" returned if URL is set' or return undef;
    $fake_vnc->called_pos_ok(2, 'hostname', 'hostname assigned');
    $fake_vnc->called_args_pos_is(2, 2, '127.0.0.1', 'hostname set to localhost');
    $fake_vnc->called_pos_ok(3, 'description', 'description assigned');
    $fake_vnc->called_args_pos_is(3, 2, 'VNC over WebSockets server provided by VMWare', 'description set accordingly');
    is_deeply \@dewebsockify_args, [12345, 'wss://foo', 'session'], 'dewebsockify called with expected args'
      or diag explain \@dewebsockify_args;
    is $vmware->host, 'foo.bar', 'hostname set';
    is $vmware->vm_id, undef, 'no VM-ID set (as our URL did not include one)';
    is $vmware->username, 'root', 'username set';
    is $vmware->password, 'secret#', 'password set (with URL-encoded character)';

    $vmware->configure_from_url('https://not-root:123@another-host/42');
    is $vmware->protocol, 'https', 'protocol configured from URL';
    is $vmware->host, 'another-host', 'host configured from URL';
    is $vmware->vm_id, '42', 'specific VM-ID configured from URL';
};

subtest 'request WebSockets URL' => sub {
    # mock ua
    my $user_agent_mock = Test::MockModule->new('Mojo::UserAgent');
    my $http = Test::MockModule->new('Mojo::Transaction::HTTP');
    my $req_mock = Test::MockModule->new('Mojo::Message::Request');
    my @fake_res = mk_res 200, '<faultstring>some error</faultstring>';
    $user_agent_mock->redefine(start => sub ($ua, $tx) { });
    $user_agent_mock->redefine(get => sub { Mojo::Transaction::HTTP->new });
    $http->redefine(result => sub { shift @fake_res });

    my $vmware = consoles::VMWare->new(vm_id => 42, host => 'mocked');
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare auth request failed: some error/, 'auth error handled';

    @fake_res = mk_res 200, '', '<faultstring>another error</faultstring>';
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare web socket URL request failed: another error/, 'ws request error handled';

    @fake_res = mk_res 200, '', 'foo';
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare did not return a web socket URL, it responsed:\nfoo/, 'no ws URL handled';

    @fake_res = mk_res 200, '', '<url>wss://</url>';
    throws_ok { $vmware->get_vmware_wss_url } qr/VMWare did not return a session cookie/, 'no cookie handled';

    @fake_res = mk_res 200, '', '<url>wss://foo.bar</url>';
    $req_mock->redefine(cookies => ['the cookie']);
    my ($url, $cookie) = $vmware->get_vmware_wss_url;
    is $url, 'wss://foo.bar', 'URL found';
    is $cookie, 'the cookie', 'cookie returned';
};

subtest 'test against real VMWare instance' => sub {
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
};

done_testing;

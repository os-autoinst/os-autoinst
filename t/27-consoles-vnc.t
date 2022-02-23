#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::Exception;
use Test::Output qw(combined_like);
use Test::MockModule;
use Test::MockObject;
use Test::Mock::Time;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::VNC;

my @sent;
my $vnc_mock = Test::MockModule->new('consoles::VNC');
$vnc_mock->redefine(_send_frame_buffer => sub ($self, $data) { push @sent, $data });
my $c = consoles::VNC->new;
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $s = Test::MockObject->new->set_true(qw(sockopt print connected close));
$s->set_series('mocked_read', 'RFB 003.006', pack('N', 1));
$s->mock('read', sub { $_[1] = $s->mocked_read; 1 });
$inet_mock->redefine(new => $s);
$vnc_mock->noop('_server_initialization');
is $c->login, '', 'can call login';

subtest 'send update request' => sub {
    $c->width(1024);
    $c->height(512);
    $c->send_update_request;
    my %expected_msg = (x => 0, y => 0, width => 1024, height => 512, incremental => 0);
    is_deeply \@sent, [\%expected_msg], 'update sent' or diag explain \@sent;
};

subtest 'handling VNC stall, malformed RFB protocol on re-connect' => sub {
    $c->check_vnc_stalls(1);
    $c->_framebuffer(1);
    $c->_vnc_stalled(1);
    $c->_last_update_received(-1000);
    $s->set_series('mocked_read', 'REB 003.006', pack('N', 1));
    combined_like {
        throws_ok {
            $c->send_update_request;
        } qr/Malformed RFB protocol: REB 003\.006/, 'dies on malformed RFB protocol';
    } qr/considering VNC stalled/, 'VNC stall logged';
    is scalar @sent, 1, 'no further message sent' or diag explain \@sent;
};

done_testing;

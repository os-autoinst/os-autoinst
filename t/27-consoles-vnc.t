#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use utf8;

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

my (@sent, @printed);
my $vnc_mock = Test::MockModule->new('consoles::VNC');
$vnc_mock->redefine(_send_frame_buffer => sub ($self, $data) { push @sent, $data });
my $c = consoles::VNC->new;
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $s = Test::MockObject->new->set_true(qw(sockopt print connected close));
sub _setup_rfb_magic { $s->set_series('mocked_read', 'RFB 003.006', pack('N', 1)) }
_setup_rfb_magic;
$s->mock(read => sub { $_[1] = $s->mocked_read; 1 });
$s->mock(print => sub { push @printed, $_[1] });
$inet_mock->redefine(new => $s);
$vnc_mock->noop('_server_initialization');
is $c->login, undef, 'can call login';
is $c->_receive_bell, 1, 'can call _receive_bell';
is_deeply \@printed, ['RFB 003.006', pack('C', 1)], 'protocol version and security type replied' or diag explain \@printed;
@printed = ();

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

subtest 'handling connect timeout' => sub {
    $bmwqemu::vars{VNC_CONNECT_TIMEOUT_LOCAL} = 5;
    $bmwqemu::vars{VNC_CONNECT_TIMEOUT_REMOTE} = 10;
    my $attempts = 0;
    $c->hostname('127.0.0.100');
    $inet_mock->redefine(new => sub { ++$attempts; undef });
    _setup_rfb_magic;
    combined_like {
        throws_ok { $c->login } 'OpenQA::Exception::VNCSetupError', 'dies on connect timeout' }
    qr/.*Error connecting to.*/, 'error logged';
    is $attempts, 7, 'login attempts for local hostname';
    $attempts = 0;
    $c->hostname('10.161.145.95');
    combined_like {
        throws_ok { $c->login } 'OpenQA::Exception::VNCSetupError', 'dies on connect timeout (2)'
    } qr/.*Error connecting to.*/, 'error logged (2)';
    is $attempts, 12, 'login attempts for remote hostname';
};

is_deeply \@printed, [], 'nothing printed so far' or diag explain \@printed;
$c->socket($s);
$c->absolute(0);

subtest 'sending pointer events' => sub {
    combined_like {
        $c->mouse_move_to(2, 3);
        $c->mouse_click(5, 7);
        $c->mouse_right_click(11, 13);
    } qr/send_pointer_event/, 'pointer events logged';
    my @expected = (
        pack(CCnn => 5, 0, 2, 3),    # mouse_move_to
        pack(CCnn => 5, 1, 5, 7),    # mouse_click (left click)
        pack(CCnn => 5, 0, 5, 7),    # mouse_click (release)
        pack(CCnn => 5, 4, 11, 13),    # mouse_right_click (right click)
        pack(CCnn => 5, 0, 11, 13),    # mouse_right_click (release)
    );
    is_deeply \@printed, \@expected, 'sent mouse move' or diag explain \@printed;
};

subtest 'sending key events' => sub {
    @printed = ();
    $c->keymap(undef);
    $c->ikvm(1);
    throws_ok { $c->map_and_send_key('ä', 1, 0.0001) } qr/No map for/, 'dies on missing key mapping';
    $c->map_and_send_key('a', 1, 0.0001);
    $c->ikvm(0);
    $c->keymap(undef);
    $c->map_and_send_key('a', undef, 0.0001);    # undef means key down and key up
    $c->map_and_send_key('@', 1, 0.0001);    # requires shift key
    my @expected = (
        pack(CxCnNx9 => 4, 2, 0, 0x4),    # single key press event for 'a' on ikvm
        pack(CCnN => 4, 1, 0, 0x61),    # key down event for 'a' on regular VNC
        pack(CCnN => 4, 0, 0, 0x61),    # key up event for 'a' on regular VNC
        pack(CCnN => 4, 1, 0, 0xffe1),    # key down event for '@' on regular VNC (shift)
        pack(CCnN => 4, 1, 0, 0x40),    # key down event for '@' on regular VNC ('@' itself)
    );
    is_deeply \@printed, \@expected, 'sent key events' or diag explain \@printed;
};

done_testing;

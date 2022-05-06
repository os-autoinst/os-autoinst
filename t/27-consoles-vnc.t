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
use cv;

cv::init;
require tinycv;

my (@sent, @printed);
my $vnc_mock = Test::MockModule->new('consoles::VNC');
$vnc_mock->redefine(_send_frame_buffer => sub ($self, $data) { push @sent, $data });
my $c = consoles::VNC->new(_bpp => 32);    # create VNC console with bit-depth of 32 bit
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $s = Test::MockObject->new->set_true(qw(sockopt print connected close blocking));
sub _setup_rfb_magic { $s->set_series('mocked_read', 'RFB 003.006', pack('N', 1)) }
_setup_rfb_magic;
$s->mock(read => sub { $_[1] = $s->mocked_read; defined $_[1] });
$s->mock($_ => sub { push @printed, $_[1] }) for qw(print write);
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

subtest 'repeating handshake with max. version' => sub {
    $s->set_series('mocked_read', 'RFB 003.106');
    $c->socket($s);
    $c->_handshake_protocol_version;
    is $c->_rfb_version, '003.008', 'RFB version set to max. supported version';
    is_deeply \@printed, ['RFB 003.008' . chr(0x0a)], 'replied max. RFB version' or diag explain \@printed;
    @printed = ();
};

subtest 'handling connect timeout' => sub {
    $bmwqemu::vars{VNC_CONNECT_TIMEOUT_LOCAL} = 5;
    $bmwqemu::vars{VNC_CONNECT_TIMEOUT_REMOTE} = 10;
    my $attempts = 0;
    $c->socket(undef);
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

subtest 'update framebuffer' => sub {
    # test with wrong data
    throws_ok { $c->update_framebuffer } qr/unsupported message type received/, 'dies on unsupported message';

    # test with truncated data
    my $update_message = pack('C', 0);
    my $one_rectangle = pack(xn => 1);
    my $of_type_zrle_with_coordinates_17_19_23_29 = pack(nnnnN => 17, 19, 23, 29, 16);
    my $expected_error = qr/Error in VNC protocol - relogin: short read for length/;
    my $logged_in = 0;
    $vnc_mock->redefine(login => sub { $logged_in = 1 });
    $s->set_series(mocked_read => $update_message, $one_rectangle, $of_type_zrle_with_coordinates_17_19_23_29);
    combined_like { $c->update_framebuffer } $expected_error, 'protocol error logged';
    ok $logged_in, 'relogin on protocol error';

    # test with full data (just one pixel, though) and vncinfo present (defines endianness and chroma subsampling)
    my $vncinfo = tinycv::new_vncinfo($c->_do_endian_conversion, $c->_true_colour, $c->_bpp / 8, 255, 0, 255, 8, 255, 16);
    my $gray_pixel = pack(CCCC => 31, 37, 41, 0);    # dark prime grey
    my $of_type_raw_with_coordinates_43_47_1_1 = pack(nnnnN => 43, 47, 1, 1, 0);
    $s->set_series(mocked_read => $update_message, $one_rectangle, $of_type_raw_with_coordinates_43_47_1_1, $gray_pixel);
    $c->_framebuffer(undef)->width(1024)->height(512)->vncinfo($vncinfo);
    ok $c->update_framebuffer, 'truthy return value for successful pixel update';
    my ($blue, $green, $red) = $c->_framebuffer->get_pixel(43, 47);
    is $blue, 41, 'pixel data updated in framebuffer (blue)';
    is $green, 37, 'pixel data updated in framebuffer (green)';
    is $red, 31, 'pixel data updated in framebuffer (red)';
};

subtest 'cutting text' => sub {
    $s->set_series(mocked_read => pack(xxxN => 1), pack(C => 0));
    ok $c->_receive_cut_text, 'text is merely discarded';
    is $s->mocked_read, undef, 'no more messages left to read';
};

subtest 'receiving color map' => sub {
    $s->set_series(mocked_read => pack(Cnn => 0, 0, 1), pack(nnn => 51 * 256, 53 * 256, 57 * 256));
    ok $c->_receive_colour_map, 'color map received';
    is $s->mocked_read, undef, 'no more messages left to read';
    my ($blue, $green, $red) = tinycv::get_colour($c->vncinfo, 0);
    is $blue, 57, 'pixel data updated in framebuffer (blue)';
    is $green, 53, 'pixel data updated in framebuffer (green)';
    is $red, 51, 'pixel data updated in framebuffer (red)';
};

subtest 'security handshake: DES' => sub {
    # assume server propose DES as only option with just zero-bytes as challenge
    $c->_rfb_version('003.007');
    $s->set_series(mocked_read => pack(C => 1), pack(C => 2), pack(NNNN => 0, 0, 0, 0), pack(N => 0));

    # let our client respond assuming some password
    @printed = ();
    $c->password('supersecret');    # only the first 8 characters will be considered
    $c->_handshake_security;
    my @expected = (
        pack(C => 2),    # client confirms to use DES
        pack(NNNN => 0x80D03992, 0xB0DB4495, 0x80D03992, 0xB0DB4495),    # client solves challenge
    );
    is_deeply \@printed, \@expected, 'expected response' or diag explain \@printed;
};

subtest 'security handshake: ikvm' => sub {
    # assume server propose ikvm as only option with 0 tunnels and '?' as session info
    $c->_rfb_version('003.007');
    $s->set_series(mocked_read => pack(C => 1), pack(C => 16), pack(N => 0), pack(C20 => 0), pack(NNNN => 0, 0, 0, 0));

    # let our client respond assuming some username and password
    @printed = ();
    $c->ikvm(1);
    $c->username('nobody');
    $c->password('supersecret');    # only the first 8 characters will be considered
    combined_like { $c->_handshake_security } qr/Session info: 00/, 'session info logged';
    my @expected = (
        pack(C => 16),    # client confirms to use ikvm
        pack(Z24 => $c->username),    # client sends username …
        pack(Z24 => $c->password)    # … and password
    );
    is $c->old_ikvm, 0, 'not considered old ikvm';
    is_deeply \@printed, \@expected, 'expected response' or diag explain \@printed;
};

subtest 'security handshake: failue' => sub {
    $c->_rfb_version('003.006');
    $s->set_series(mocked_read => pack(N => 42));
    throws_ok { $c->_handshake_security } qr/security/, 'dies on unknown security type';

    $s->set_series(mocked_read => pack(N => 1));
    $s->set_false('connected');
    throws_ok { $c->_handshake_security } qr/login failed/, 'dies when socket closed';
};

done_testing;

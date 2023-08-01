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

$bmwqemu::scriptdir = "$Bin/..";

my (@sent, @printed);
my $vnc_mock = Test::MockModule->new('consoles::VNC');
$vnc_mock->redefine(_send_frame_buffer => sub ($self, $data) { push @sent, $data });
my $c = consoles::VNC->new(_bpp => 32);    # create VNC console with bit-depth of 32 bit
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $s = Test::MockObject->new->set_true(qw(sockopt fileno print connected close blocking));
sub _setup_rfb_magic () { $s->set_series('mocked_read', 'RFB 003.006', pack('N', 1)) }
_setup_rfb_magic;
$s->mock(read => sub { $_[1] = $s->mocked_read; defined $_[1] });
$s->mock($_ => sub { push @printed, $_[1] }) for qw(print write);
$inet_mock->redefine(new => $s);
$vnc_mock->noop('_server_initialization');
combined_like { is $c->login, undef, 'can call login' } qr/socket timeout/, 'would have set socket timeout';
is $c->_receive_bell, 1, 'can call _receive_bell';
is_deeply \@printed, ['RFB 003.006', pack('C', 1)], 'protocol version and security type replied' or diag explain \@printed;
@printed = ();

# ensure endian conversion is setup correctly (despite initially mocking _server_initialization)
my $machine_is_big_endian = unpack('h*', pack('s', 1)) =~ /01/ ? 1 : 0;
my %normal_update_request = (x => 0, y => 0, width => 1024, height => 512, incremental => 0);

subtest 'send update request' => sub {
    $c->width(1024)->height(512)->send_update_request;
    is_deeply \@sent, [\%normal_update_request], 'update sent' or diag explain \@sent;
};

subtest 'send forced update request' => sub {
    @sent = ();
    $c->width(1024)->height(512)->_last_update_received(0)->_framebuffer(1)->check_vnc_stalls(1)->send_update_request;
    my %forced_update_request = (x => 0, y => 0, width => 16, height => 16, incremental => 0);
    is_deeply \@sent, [\%forced_update_request, \%normal_update_request], 'update sent' or diag explain \@sent;
};

subtest 'handling VNC stall, malformed RFB protocol on re-connect' => sub {
    @sent = ();
    $c->check_vnc_stalls(1)->_framebuffer(1)->_vnc_stalled(1)->_last_update_received(-1000);
    $s->set_series('mocked_read', 'REB 003.006', pack('N', 1));
    combined_like {
        throws_ok {
            $c->send_update_request;
        } qr/Malformed RFB protocol: REB 003\.006/, 'dies on malformed RFB protocol';
    } qr/considering VNC stalled/, 'VNC stall logged';
    is scalar @sent, 0, 'no further message sent' or diag explain \@sent;
};

subtest 'repeating handshake with max. version' => sub {
    $s->set_series('mocked_read', 'RFB 003.106');
    $c->socket($s);
    $c->_handshake_protocol_version;
    is $c->_rfb_version, '003.008', 'RFB version set to max. supported version';
    is_deeply \@printed, ['RFB 003.008' . chr(0x0a)], 'replied max. RFB version' or diag explain \@printed;
    @printed = ();
};

subtest 'setting socket timeout' => sub {
    my %socket_args;
    $bmwqemu::vars{VNC_TIMEOUT_REMOTE} = 6;
    $inet_mock->redefine(new => sub ($class, @args) { %socket_args = @args; $s });
    $c->hostname('10.161.145.95');
    combined_like { throws_ok { $c->login } qr/unexpected end of data/, 'login dies on unexpected end of data' }
      qr/warn.*login.*Unable to set VNC socket timeout: .+/, 'timeout would have been passed to socket';
    is $socket_args{Timeout}, 6, 'remote timeout passed to socket constructor' or diag explain \%socket_args;
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
    throws_ok { $c->map_and_send_key('ä', 1, 0.0001) } qr/No map for 'ä'/, 'dies on missing key mapping';
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
    $c->_do_endian_conversion($machine_is_big_endian);    # assume server is little-endian
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

    my $last_rectangle = pack(nnnnN => 0, 0, 0, 0, -224);
    $s->set_series(mocked_read => $update_message, $one_rectangle, $last_rectangle);
    ok $c->update_framebuffer, 'truthy return value last rectangle';

    my $unknown_encoding = pack(nnnnN => 0, 0, 0, 0, -225);
    $s->set_series(mocked_read => $update_message, $one_rectangle, $unknown_encoding);
    throws_ok { $c->update_framebuffer } qr/unsupported update encoding -225/, 'dies on unsupported encoding';
    is $s->mocked_read, undef, 'no more messages left to read after reading unknown encoding';

    # test with full data again, assuming the server is big-endian
    $c->_do_endian_conversion(!$machine_is_big_endian);    # assume server is big-endian
    $vncinfo = tinycv::new_vncinfo($c->_do_endian_conversion, $c->_true_colour, $c->_bpp / 8, 255, 0, 255, 8, 255, 16);
    $gray_pixel = pack(CCCC => 0, 41, 37, 31);    # dark prime grey
    $s->set_series(mocked_read => $update_message, $one_rectangle, $of_type_raw_with_coordinates_43_47_1_1, $gray_pixel);
    $c->_framebuffer(undef)->width(1024)->height(512)->vncinfo($vncinfo);
    ok $c->update_framebuffer, 'truthy return value for successful pixel update of big-endian server';
    ($blue, $green, $red) = $c->_framebuffer->get_pixel(43, 47);
    is $blue, 41, 'pixel data updated in framebuffer (blue, big-endian server)';
    is $green, 37, 'pixel data updated in framebuffer (green, big-endian server)';
    is $red, 31, 'pixel data updated in framebuffer (red, big-endian server)';

    $c->ikvm(1);
    my $unsupported_ikvm_encoding = pack(nnnnN => 0, 0, 1, 1, 88);
    my $ikvm_specific_data = pack(NN => 0, 9);    # some "prefix" and data length
    $s->set_series(mocked_read => $update_message, $one_rectangle, $unsupported_ikvm_encoding, $ikvm_specific_data);
    throws_ok { $c->update_framebuffer } qr/unsupported encoding 88/, 'dies on unsupported ikvm encoding';

    my $ikvm_encoding = pack(nnnnN => 0, 0, 2, 2, 89);    # 2x2 pixels at 0,0
    my $surplus_byte = pack(CC => 1);    # will be ignored
    my $actual_image_data = pack(NN => 0xFFFFFFE0, 0xFFFFFFE0);    # white pixels
    $s->set_series(mocked_read => $update_message, $one_rectangle, $ikvm_encoding, $ikvm_specific_data, $surplus_byte, $actual_image_data);
    combined_like { $c->update_framebuffer } qr/Additional Bytes: 01/, 'additional bytes skipped';
    ($blue, $green, $red) = $c->_framebuffer->get_pixel(0, 0);
    is $c->_framebuffer->xres, 2, 'xres updated';
    is $c->_framebuffer->yres, 2, 'yres updated';
    is $blue, 248, 'pixel data updated in framebuffer via ikvm encoding (blue)';
    is $green, 248, 'pixel data updated in framebuffer via ikvm encoding (green)';
    is $red, 248, 'pixel data updated in framebuffer via ikvm encoding (red)';

    my $raw_ikvm_encoding = pack(nnnnN => 0, 0, 2, 2, 0);    # 2x2 pixels at 0,0
    my $raw_ikvm_segment = pack(CxNN => 0, 1, 1);    # one segment of length 1 and type 0
    my $raw_ikvm_data = pack(nnCC => 0, 0, 0, 0);    # coordinates are 0,0
    my $raw_ikvm_data2 = pack('C[512]' => 0);    # just provide zeros for the image data
    $s->set_series(mocked_read => $update_message, $one_rectangle, $raw_ikvm_encoding, $ikvm_specific_data, $raw_ikvm_segment, $raw_ikvm_data, $raw_ikvm_data2);
    $c->update_framebuffer;

    $raw_ikvm_encoding = pack(nnnnN => 0, 0, -1, 0, 0);    # negative width, supposed to turn screen off
    $s->set_series(mocked_read => $update_message, $one_rectangle, $raw_ikvm_encoding, $ikvm_specific_data, $raw_ikvm_segment, $raw_ikvm_data, $raw_ikvm_data2);
    $c->update_framebuffer;
    is $c->_framebuffer, undef, 'framebuffer removed';
    ok !$c->screen_on, 'screen turned off by negative with';

    @printed = ();
    $ikvm_encoding = pack(nnnnN => 0, 0, 2, 2, 87);    # 2x2 pixels at 0,0, ast2100 encoded
    $actual_image_data = pack(CCn => 10, 11, 444);    # anything but high quality
    $s->set_series(mocked_read => $update_message, $one_rectangle, $ikvm_encoding, $ikvm_specific_data, $actual_image_data);
    combined_like { $c->update_framebuffer } qr/fixing quality/, 'enforcing high quality';
    is_deeply \@printed, [pack(CCCn => 0x32, 0, 11, 444)], 'high quality requested' or diag explain \@printed;
    ok $c->_framebuffer, 'framebuffer present again';
    ok $c->screen_on, 'screen on again';

    $actual_image_data = pack(CCnN => 11, 11, 444, 0x90);    # high quality, ctrl 9 for stopping ast2100 decoding early
    $ikvm_specific_data = pack(NN => 0, length($actual_image_data));    # some "prefix" and data length
    $s->set_series(mocked_read => $update_message, $one_rectangle, $ikvm_encoding, $ikvm_specific_data, $actual_image_data);
    $c->update_framebuffer;
    is scalar @printed, 1, 'no further image requested' or diag explain \@printed;
};

subtest 'read special messages/encodings' => sub {
    $s->set_series(mocked_read => pack(C => 51), pack(N => 0));
    combined_like { $c->update_framebuffer } qr/discarding 4 bytes for message 51/, 'ikvm message discarded';
    is $s->mocked_read, undef, 'no more messages left to read after discarding';

    $s->set_series(mocked_read => pack(C => 0x39), pack(NNZ256 => 1, 2, 3));
    combined_like { $c->update_framebuffer } qr/IKVM Session Message: 1 2 3/, 'ikvm session logged';
    is $s->mocked_read, undef, 'no more messages left to read after discarding';
};

subtest 'cutting text' => sub {
    $s->set_series(mocked_read => pack(xxxN => 1), pack(C => 0));
    ok $c->_receive_cut_text, 'text is merely discarded';
    is $s->mocked_read, undef, 'no more messages left to read';
};

subtest 'receiving color map' => sub {
    $s->set_series(mocked_read => pack(Cnn => 0, 0, 1), pack(nnn => 51 * 256, 53 * 256, 57 * 256));
    $c->ikvm(0);
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

subtest 'server initialization' => sub {
    $vnc_mock->unmock('_server_initialization');
    @printed = ();

    my $framebuffer_width = 1024;
    my $framebuffer_height = 512;
    my $bits_per_pixel = 32;
    my $depth = 32;
    my $server_is_big_endian = 0;
    my $true_colour_flag = 1;
    my $name_length = 0;
    my $red_max = 255;
    my $green_max = 255;
    my $blue_max = 255;
    my $red_shift = 0;
    my $green_shift = 8;
    my $blue_shift = 16;
    my $server_init = pack(nnCCCCnnnCCCxxxN => $framebuffer_width, $framebuffer_height,
        $bits_per_pixel, $depth, $server_is_big_endian, $true_colour_flag,
        $red_max, $green_max, $blue_max, $red_shift, $green_shift, $blue_shift, $name_length);
    my $ikvm_init = pack(x4NCCCC => 1, 2, 3, 4, 5);

    # test as ikvm taking setpixelformat from server
    $s->set_series(mocked_read => $server_init, $ikvm_init);
    $c->depth(undef)->ikvm(1);
    combined_like { $c->_server_initialization } qr/IKVM specifics: 1 2 3 4 5/, 'ikvm specifics logged';
    is $c->depth, 32, 'depth assigned';
    is_deeply \@printed, [], 'no further messages sent for ikvm' or diag explain \@printed;

    # test as dell requesting 16-bit setpixelformat
    $s->set_series(mocked_read => $server_init);
    $c->depth(16)->ikvm(0)->dell(1);
    $c->_server_initialization;
    # expect params for 16-bit depth being replied as setpixelformat
    $bits_per_pixel = $depth = 16;
    $red_max = $green_max = $blue_max = 31;
    $red_shift = 10;
    $green_shift = 5;
    $blue_shift = 0;
    my @params = ($bits_per_pixel, $depth, ($server_is_big_endian && $machine_is_big_endian), $true_colour_flag, $red_max, $green_max, $blue_max, $red_shift, $green_shift, $blue_shift);
    my @expected = (
        pack(CCCCCCCCnnnCCCCCC => 0, 0, 0, 0, @params, 0, 0, 0),    # setpixelformat
        pack(CCn => 2, 0, 5),    # five supported encodings (no ZRLE due to dell flag)
        pack(N => 0000),    # raw
        pack(N => -223),    # DesktopSize
        pack(N => -224),    # VNC_ENCODING_LAST_RECT
        pack(N => -257),    # VNC_ENCODING_POINTER_TYPE_CHANGE
        pack(N => -261),    # VNC_ENCODING_LED_STATE
    );
    is_deeply \@printed, \@expected, 'pixel format and encodings replied' or diag explain \@printed;
};

subtest 'login on real VNC server via vnctest, request and receive frame buffer' => sub {
    # This test is using `vnctest` so this script is covered as well. Note that the `vnctest` script has mainly been added to be able to run our VNC client
    # code manually against a real VNC server (which can sometimes be useful).

    my $display = $ENV{VNC_TEST_DISPLAY} // 20;
    my $port = 5900 + $display;

    note "running Xvnc for display $display (port $port) and connect via $bmwqemu::scriptdir/vnctest";
    my $xvnc_pid = open(my $xvnc_pipe, "Xvnc -depth 16 -SecurityTypes None -ac :$display 2>&1 |");
    my $vnc_test_pid = open(my $vnc_test_pipe, "$bmwqemu::scriptdir/vnctest --port $port --verbose 2>&1 |");
    my ($sent_update_request, $has_framebuffer) = (0, 0);
    while (my $line = <$vnc_test_pipe>) {
        ++$sent_update_request if $line =~ qr/Send update request/;
        ++$has_framebuffer if $line =~ qr/has frame buffer/;
        last if $sent_update_request && $has_framebuffer;
    }
    kill SIGTERM => $_ for $xvnc_pid, $vnc_test_pid;
    waitpid $_, 0 for $xvnc_pid, $vnc_test_pid;
    close $_ for $xvnc_pipe, $vnc_test_pipe;

    ok $sent_update_request, 'sent update request';
    ok $has_framebuffer, 'received frame buffer';
};

done_testing;

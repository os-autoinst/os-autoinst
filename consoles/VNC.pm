package consoles::VNC;
use strict;
use warnings;
use base 'Class::Accessor::Fast';
use IO::Socket::INET;
use bytes;
use bmwqemu 'diag';
use Time::HiRes qw( usleep gettimeofday time );
use Carp;
use List::Util 'min';

use Crypt::DES;
use Compress::Raw::Zlib;

use Carp qw(confess cluck carp croak);
use Data::Dumper 'Dumper';
use feature 'say';

__PACKAGE__->mk_accessors(
    qw(hostname port username password socket name width height depth
      no_endian_conversion  _pixinfo _colourmap _framebuffer _rfb_version screen_on
      _bpp _true_colour _do_endian_conversion absolute ikvm keymap _last_update_received
      _last_update_requested _vnc_stalled vncinfo old_ikvm dell
      ));
our $VERSION = '0.40';

my $MAX_PROTOCOL_VERSION = 'RFB 003.008' . chr(0x0a);    # Max version supported

# This line comes from perlport.pod
my $client_is_big_endian = unpack('h*', pack('s', 1)) =~ /01/ ? 1 : 0;

# The numbers in the hashes below were acquired from the VNC source code
my %supported_depths = (
    32 => {                                              # same as 24 actually
        bpp         => 32,
        true_colour => 1,
        red_max     => 255,
        green_max   => 255,
        blue_max    => 255,
        red_shift   => 16,
        green_shift => 8,
        blue_shift  => 0,
    },
    24 => {
        bpp         => 32,
        true_colour => 1,
        red_max     => 255,
        green_max   => 255,
        blue_max    => 255,
        red_shift   => 16,
        green_shift => 8,
        blue_shift  => 0,
    },
    16 => {    # same as 15
        bpp         => 16,
        true_colour => 1,
        red_max     => 31,
        green_max   => 31,
        blue_max    => 31,
        red_shift   => 10,
        green_shift => 5,
        blue_shift  => 0,
    },
    15 => {
        bpp         => 16,
        true_colour => 1,
        red_max     => 31,
        green_max   => 31,
        blue_max    => 31,
        red_shift   => 10,
        green_shift => 5,
        blue_shift  => 0
    },
    8 => {
        bpp         => 8,
        true_colour => 0,
        red_max     => 8,
        green_max   => 8,
        blue_max    => 4,
        red_shift   => 5,
        green_shift => 2,
        blue_shift  => 0,
    },
);

my @encodings = (

    # These ones are defined in rfbproto.pdf
    {
        num       => 0,
        name      => 'Raw',
        supported => 1,
    },
    {
        num       => 16,
        name      => 'ZRLE',
        supported => 1,
    },
    {
        num       => -223,
        name      => 'DesktopSize',
        supported => 1,
    },
    {
        num       => -257,
        name      => 'VNC_ENCODING_POINTER_TYPE_CHANGE',
        supported => 1,
    },
    {
        num       => -261,
        name      => 'VNC_ENCODING_LED_STATE',
        supported => 1,
    },
);

sub login {
    my ($self, $connect_timeout) = @_;
    $connect_timeout //= 10;
    # arbitrary
    my $connect_failure_limit = 2;

    $self->width(0);
    $self->height(0);
    $self->screen_on(1);
    # in a land far far before our time
    $self->_last_update_received(0);
    $self->_last_update_requested(0);
    $self->_vnc_stalled(0);

    my $hostname = $self->hostname || 'localhost';
    my $port     = $self->port     || 5900;

    my $endtime = time + $connect_timeout;

    my $socket;
    my $err_cnt = 0;
    while (!$socket) {
        $socket = IO::Socket::INET->new(
            PeerAddr => $hostname,
            PeerPort => $port,
            Proto    => 'tcp',
        );
        if (!$socket) {
            $err_cnt++;
            return if (time > $endtime);
            # we might be too fast trying to connect to the VNC host (e.g.
            # qemu) so ignore the first occurences of a failed
            # connection attempt.
            bmwqemu::diag "Error connecting to host <$hostname>: $@" if $err_cnt > $connect_failure_limit;
            sleep 1;
            next;
        }
        $socket->sockopt(Socket::TCP_NODELAY, 1);    # turn off Naegle's algorithm for vnc
    }
    $self->socket($socket);

    eval {
        $self->_handshake_protocol_version();
        $self->_handshake_security();
        $self->_client_initialization();
        $self->_server_initialization();
    };
    my $error = $@;                                  # store so it doesn't get overwritten
    if ($error) {

        # clean up so socket can be garbage collected
        $self->socket(undef);
        die $error;
    }
}

sub _handshake_protocol_version {
    my ($self) = @_;

    my $socket = $self->socket;
    $socket->read(my $protocol_version, 12) || die 'unexpected end of data';

    #bmwqemu::diag "prot: $protocol_version";

    my $protocol_pattern = qr/\A RFB [ ] (\d{3}\.\d{3}) \s* \z/xms;
    if ($protocol_version !~ m/$protocol_pattern/xms) {
        die 'Malformed RFB protocol: ' . $protocol_version;
    }
    $self->_rfb_version($1);

    if ($protocol_version gt $MAX_PROTOCOL_VERSION) {
        $protocol_version = $MAX_PROTOCOL_VERSION;

        # Repeat with the changed version
        if ($protocol_version !~ m/$protocol_pattern/xms) {
            die 'Malformed RFB protocol';
        }
        $self->_rfb_version($1);
    }

    if ($self->_rfb_version lt '003.003') {
        die 'RFB protocols earlier than v3.3 are not supported';
    }

    # let's use the same version of the protocol, or the max, whichever's lower
    $socket->print($protocol_version);
}

sub _handshake_security {
    my $self = shift;

    my $socket = $self->socket;

    # Retrieve list of security options
    my $security_type;
    if ($self->_rfb_version ge '003.007') {
        my $number_of_security_types = 0;
        my $r = $socket->read($number_of_security_types, 1);
        if ($r) {
            $number_of_security_types = unpack('C', $number_of_security_types);
        }
        if ($number_of_security_types == 0) {
            die 'Error authenticating';
        }

        my @security_types;
        foreach (1 .. $number_of_security_types) {
            $socket->read(my $security_type, 1)
              || die 'unexpected end of data';
            $security_type = unpack('C', $security_type);

            push @security_types, $security_type;
        }

        my @pref_types = (1, 2);
        @pref_types = (30, 1, 2) if $self->username;
        @pref_types = (16) if $self->ikvm;

        for my $preferred_type (@pref_types) {
            if (0 < grep { $_ == $preferred_type } @security_types) {
                $security_type = $preferred_type;
                last;
            }
        }
    }
    else {

        # In RFB 3.3, the server dictates the security type
        $socket->read($security_type, 4) || die 'unexpected end of data';
        $security_type = unpack('N', $security_type);
    }

    if ($security_type == 1) {

        # No authorization needed!
        if ($self->_rfb_version ge '003.007') {
            $socket->print(pack('C', 1));
        }

    }
    elsif ($security_type == 2) {

        # DES-encrypted challenge/response

        if ($self->_rfb_version ge '003.007') {
            $socket->print(pack('C', 2));
        }

        # # VNC authentication is to be used and protocol data is to be
        # # sent unencrypted. The server sends a random 16-byte
        # # challenge:

        # # No. of bytes Type [Value] Description
        # # 16 U8 challenge


        $socket->read(my $challenge, 16)
          || die 'unexpected end of data';

        # the RFB protocol only uses the first 8 characters of a password
        my $key = substr($self->password, 0, 8);
        $key = '' if (!defined $key);
        $key .= pack('C', 0) until (length($key) % 8) == 0;

        my $realkey;

        foreach my $byte (split //, $key) {
            $realkey .= pack('b8', scalar reverse unpack('b8', $byte));
        }

        # # The client encrypts the challenge with DES, using a password
        # # supplied by the user as the key, and sends the resulting
        # # 16-byte response:
        # # No. of bytes Type [Value] Description
        # # 16 U8 response

        my $cipher = Crypt::DES->new($realkey);
        my $response;
        my $i = 0;

        while ($i < 16) {
            my $word = substr($challenge, $i, 8);

            $response .= $cipher->encrypt($word);
            $i += 8;
        }
        $socket->print($response);

    }
    elsif ($security_type == 16) {    # ikvm

        $socket->print(pack('C',   16));                # accept
        $socket->write(pack('Z24', $self->username));
        $socket->write(pack('Z24', $self->password));
        $socket->read(my $num_tunnels, 4);

        $num_tunnels = unpack('N', $num_tunnels);
        # found in https://github.com/kanaka/noVNC
        if ($num_tunnels > 0x1000000) {
            $self->old_ikvm(1);
        }
        else {
            $self->old_ikvm(0);
        }
        $socket->read(my $ikvm_session, 20) || die 'unexpected end of data';
        my @bytes = unpack("C20", $ikvm_session);
        print "Session info: ";
        for my $b (@bytes) {
            printf "%02x ", $b;
        }
        print "\n";
        # examples
        # af f9 ff bc 50 0d 02 00 20 a3 00 00 84 4c e3 be 00 80 41 40 d0 24 01 00
        # af f9 1f bd 00 06 02 00 20 a3 00 00 84 4c e3 be 00 80 41 40 d0 24 01 00
        # af f9 bf bc 08 03 02 00 20 a3 00 00 84 4c e3 be 00 80 41 40 d0 24 01 00
        # af f9 ff bd 40 19 02 00 b0 a4 00 00 84 8c b1 be 00 60 43 40 f0 29 01 00
        # ab f9 1f be 08 13 02 00 e0 a5 00 00 74 a8 82 be 00 00 4b 40 d8 2d 01 00
        $socket->read(my $security_result, 4) || die 'Failed to login';
        $security_result = unpack('C', $security_result);
        print "Security Result: $security_result\n";
        if ($security_result != 0) {
            die 'Failed to login';
        }
    }
    else {
        die 'VNC Server wants security, but we have no password';
    }

    # the RFB protocol always returns a result for type 2,
    # but type 1, only for 003.008 and up
    if (($self->_rfb_version ge '003.008' && $security_type == 1)
        || $security_type == 2)
    {
        $socket->read(my $security_result, 4)
          || die 'unexpected end of data';
        $security_result = unpack('N', $security_result);

        die 'login failed' if $security_result;
    }
    elsif (!$socket->connected) {
        die 'login failed';
    }
}

sub _bin_int {
    my ($self, $s) = @_;
    my @a = unpack("C*", $s);
    my $r = 0;
    for (my $i = 0; $i < @a; $i++) {
        $r = 256 * $r;
        $r += $a[$i];
    }
    return $r;
}

sub _client_initialization {
    my $self = shift;

    my $socket = $self->socket;

    $socket->print(pack('C', !$self->ikvm));    # share
}

sub _server_initialization {
    my $self = shift;

    my $socket = $self->socket;
    $socket->read(my $server_init, 24) || die 'unexpected end of data';

    #<<< tidy off
    my ( $framebuffer_width, $framebuffer_height,
	 $bits_per_pixel, $depth, $server_is_big_endian, $true_colour_flag,
	 %pixinfo,
	 $name_length );
    ( $framebuffer_width,  $framebuffer_height,
      $bits_per_pixel, $depth, $server_is_big_endian, $true_colour_flag,
      $pixinfo{red_max},   $pixinfo{green_max},   $pixinfo{blue_max},
      $pixinfo{red_shift}, $pixinfo{green_shift}, $pixinfo{blue_shift},
      $name_length
    ) = unpack 'nnCCCCnnnCCCxxxN', $server_init;
    #>>> tidy on

    if (!$self->depth) {

        # client did not express a depth preference, so check if the server's preference is OK
        if (!$supported_depths{$depth}) {
            die 'Unsupported depth ' . $depth;
        }
        if ($bits_per_pixel != $supported_depths{$depth}->{bpp}) {
            die 'Unsupported bits-per-pixel value ' . $bits_per_pixel;
        }
        if (
            $true_colour_flag ?
            !$supported_depths{$depth}->{true_colour}
            : $supported_depths{$depth}->{true_colour})
        {
            die 'Unsupported true colour flag';
        }
        $self->depth($depth);

        # Use server's values for *_max and *_shift

    }
    elsif ($depth != $self->depth) {
        for my $key (qw(red_max green_max blue_max red_shift green_shift blue_shift)) {
            $pixinfo{$key} = $supported_depths{$self->depth}->{$key};
        }
    }
    $self->absolute($self->ikvm // 0);

    if (!$self->width && !$self->ikvm) {
        $self->width($framebuffer_width);
    }
    if (!$self->height && !$self->ikvm) {
        $self->height($framebuffer_height);
    }
    $self->_pixinfo(\%pixinfo);
    $self->_bpp($supported_depths{$self->depth}->{bpp});
    $self->_true_colour($supported_depths{$self->depth}->{true_colour});
    $self->_do_endian_conversion($self->no_endian_conversion ? 0 : $server_is_big_endian != $client_is_big_endian);

    if ($name_length) {
        $socket->read(my $name_string, $name_length)
          || die 'unexpected end of data';
        $self->name($name_string);
    }

    if ($self->ikvm) {
        $socket->read(my $ikvm_init, 12) || die 'unexpected end of data';

        my ($current_thread, $ikvm_video_enable, $ikvm_km_enable, $ikvm_kick_enable, $v_usb_enable) = unpack 'x4NCCCC', $ikvm_init;
        print "IKVM specifics: $current_thread $ikvm_video_enable $ikvm_km_enable $ikvm_kick_enable $v_usb_enable\n";
        die "Can't use keyboard and mouse.  Is another ipmi vnc viewer logged in?" unless $ikvm_km_enable;
        return;    # the rest is kindly ignored by ikvm anyway
    }

    my $info = tinycv::new_vncinfo(
        $self->_do_endian_conversion, $self->_true_colour,   $self->_bpp / 8,    $pixinfo{red_max}, $pixinfo{red_shift},
        $pixinfo{green_max},          $pixinfo{green_shift}, $pixinfo{blue_max}, $pixinfo{blue_shift});
    $self->vncinfo($info);

    # setpixelformat
    $socket->print(
        pack(
            'CCCCCCCCnnnCCCCCC',
            0,     # message_type
            0,     # padding
            0,     # padding
            0,     # padding
            $self->_bpp,
            $self->depth,
            $self->_do_endian_conversion,
            $self->_true_colour,
            $pixinfo{red_max},
            $pixinfo{green_max},
            $pixinfo{blue_max},
            $pixinfo{red_shift},
            $pixinfo{green_shift},
            $pixinfo{blue_shift},
            0,     # padding
            0,     # padding
            0,     # padding
        ));

    # set encodings

    my @encs = grep { $_->{supported} } @encodings;

    # Prefer the higher-numbered encodings
    @encs = reverse sort { $a->{num} <=> $b->{num} } @encs;

    if ($self->dell) {
        # idrac's zlre implementation even kills tigervnc, they duplicate
        # frames under certain conditions. Raw works ok
        @encs = grep { $_->{name} ne 'ZRLE' } @encs;
    }
    $socket->print(
        pack(
            'CCn',
            2,               # message_type
            0,               # padding
            scalar @encs,    # number_of_encodings
        ));
    for my $enc (@encs) {

        # Make a big-endian, signed 32-bit value
        # method:
        #   pack as own-endian, signed      e.g. -239
        #   unpack as own-endian, unsigned  e.g. 4294967057
        #   pack as big-endian
        my $num = pack 'N', unpack 'L', pack 'l', $enc->{num};
        $socket->print($num);
    }
}

sub _send_key_event {
    my ($self, $down_flag, $key) = @_;

    # A key press or release. Down-flag is non-zero (true) if the key is now pressed, zero
    # (false) if it is now released. The key itself is specified using the “keysym” values
    # defined by the X Window System.

    my $socket   = $self->socket;
    my $template = 'CCnN';
    # for a strange reason ikvm has a lot more padding
    $template = 'CxCnNx9' if $self->ikvm;
    $socket->print(
        pack(
            $template,
            4,             # message_type
            $down_flag,    # down-flag
            0,             # padding
            $key,          # key
        ));
}

sub send_key_event_down {
    my ($self, $key) = @_;
    $self->_send_key_event(1, $key);
}

sub send_key_event_up {
    my ($self, $key) = @_;
    $self->_send_key_event(0, $key);
}

sub send_key_event {
    my ($self, $key) = @_;
    $self->send_key_event_down($key);
    usleep(50);    # just a brief moment
    $self->send_key_event_up($key);
}


## no critic (HashKeyQuotes)

my $keymap_x11 = {
    'esc'       => 0xff1b,
    'down'      => 0xff54,
    'right'     => 0xff53,
    'up'        => 0xff52,
    'left'      => 0xff51,
    'equal'     => ord('='),
    'spc'       => ord(' '),
    'minus'     => ord('-'),
    'shift'     => 0xffe1,
    'ctrl'      => 0xffe3,     # left, right is e4
    'caps'      => 0xffe5,
    'meta'      => 0xffe7,     # left, right is e8
    'alt'       => 0xffe9,     # left one, right is ea
    'ret'       => 0xff0d,
    'tab'       => 0xff09,
    'backspace' => 0xff08,
    'end'       => 0xff57,
    'delete'    => 0xffff,
    'home'      => 0xff50,
    'insert'    => 0xff63,
    'pgup'      => 0xff55,
    'pgdn'      => 0xff56,
    'sysrq'     => 0xff15,
    'super'     => 0xffeb,     # left, right is ec
};

# ikvm aka USB: https://www.win.tue.nl/~aeb/linux/kbd/scancodes-14.html
my $keymap_ikvm = {
    'ctrl'   => 0xe0,
    'shift'  => 0xe1,
    'alt'    => 0xe2,
    'meta'   => 0xe3,
    'caps'   => 0x39,
    'sysrq'  => 0x9a,
    'end'    => 0x4d,
    'delete' => 0x4c,
    'home'   => 0x4a,
    'insert' => 0x49,
    'super'  => 0xe3,

    #    {NSPrintScreenFunctionKey, 0x46},
    # {NSScrollLockFunctionKey, 0x47},
    # {NSPauseFunctionKey, 0x48},

    'pgup' => 0x4b,
    'pgdn' => 0x4e,

    'left'  => 0x50,
    'right' => 0x4f,
    'up'    => 0x52,
    'down'  => 0x51,

    '0'         => 0x27,
    'ret'       => 0x28,
    'esc'       => 0x29,
    'backspace' => 0x2a,
    'tab'       => 0x2b,
    ' '         => 0x2c,
    'spc'       => 0x2c,
    'minus'     => 0x2d,
    '='         => 0x2e,
    '['         => 0x2f,
    ']'         => 0x30,
    '\\'        => 0x31,
    ';'         => 0x33,
    '\''        => 0x34,
    '`'         => 0x35,
    ','         => 0x36,
    '.'         => 0x37,
    '/'         => 0x38,
};

sub shift_keys {

    # see http://en.wikipedia.org/wiki/IBM_PC_keyboard
    return {
        '~' => '`',
        '!' => '1',
        '@' => '2',
        '#' => '3',
        '$' => '4',
        '%' => '5',
        '^' => '6',
        '&' => '7',
        '*' => '8',
        '(' => '9',
        ')' => '0',
        '_' => 'minus',
        '+' => '=',

        # second line
        '{' => '[',
        '}' => ']',
        '|' => '\\',

        # third line
        ':' => ';',
        '"' => '\'',

        # fourth line
        '<' => ',',
        '>' => '.',
        '?' => '/',
    };
}

## use critic

sub init_x11_keymap {
    my ($self) = @_;

    return if $self->keymap;
    # create a deep copy - we want to reuse it in other instances
    my %keymap = %$keymap_x11;

    for my $key (30 .. 255) {
        $keymap{chr($key)} ||= $key;
    }
    for my $key (1 .. 12) {
        $keymap{"f$key"} = 0xffbd + $key;
    }
    for my $key ("a" .. "z") {
        $keymap{$key} = ord($key);
        # shift-H looks strange, but that's how VNC works
        $keymap{uc $key} = [$keymap{shift}, ord(uc $key)];
    }
    # VNC doesn't use the unshifted values, only prepends a shift key
    for my $key (keys %{shift_keys()}) {
        die "no map for $key" unless $keymap{$key};
        $keymap{$key} = [$keymap{shift}, $keymap{$key}];
    }
    $self->keymap(\%keymap);
}

sub init_ikvm_keymap {
    my ($self) = @_;

    return if $self->keymap;
    my %keymap = %$keymap_ikvm;
    for my $key ("a" .. "z") {
        my $code = 0x4 + ord($key) - ord('a');
        $keymap{$key} = $code;
        $keymap{uc $key} = [$keymap{shift}, $code];
    }
    for my $key ("1" .. "9") {
        $keymap{$key} = 0x1e + ord($key) - ord('1');
    }
    for my $key (1 .. 12) {
        $keymap{"f$key"} = 0x3a + $key - 1,;
    }
    my %map = %{shift_keys()};
    while (my ($key, $shift) = each %map) {
        die "no map for $key" unless $keymap{$shift};
        $keymap{$key} = [$keymap{shift}, $keymap{$shift}];
    }
    $self->keymap(\%keymap);
}


sub map_and_send_key {
    my ($self, $keys, $down_flag) = @_;

    if ($self->ikvm) {
        $self->init_ikvm_keymap;
    }
    else {
        $self->init_x11_keymap;
    }

    my @events;

    for my $key (split('-', $keys)) {
        if (defined($self->keymap->{$key})) {
            if (ref($self->keymap->{$key}) eq 'ARRAY') {
                push(@events, @{$self->keymap->{$key}});
            }
            else {
                push(@events, $self->keymap->{$key});
            }
            next;
        }
        else {
            die "No map for '$key'";
        }
    }

    if ($self->ikvm && @events == 1) {
        $self->_send_key_event(2, $events[0]);
        return;
    }

    if (!defined $down_flag || $down_flag == 1) {
        for my $key (@events) {
            $self->send_key_event_down($key);
        }
    }
    usleep(50);    # just a brief moment
    if (!defined $down_flag || $down_flag == 0) {
        for my $key (@events) {
            $self->send_key_event_up($key);
        }
    }
}

sub send_pointer_event {
    my ($self, $button_mask, $x, $y) = @_;
    bmwqemu::diag "send_pointer_event $button_mask, $x, $y, " . $self->absolute;

    my $template = 'CCnn';
    $template = 'CxCnnx11' if ($self->ikvm);

    $self->socket->print(
        pack(
            $template,
            5,               # message type
            $button_mask,    # button-mask
            $x,              # x-position
            $y,              # y-position
        ));
}

# drain the VNC socket from all pending incoming messages.  return
# true if there was a screen update.
sub update_framebuffer() {    # upstream VNC.pm:  "capture"
    my ($self) = @_;

    my $have_recieved_update = 0;
    while (defined(my $message_type = $self->_receive_message())) {
        $have_recieved_update = 1 if $message_type == 0;
    }
    return $have_recieved_update;
}

use POSIX ':errno_h';

sub _send_frame_buffer {
    my ($self, $args) = @_;

    return $self->socket->print(
        pack(
            'CCnnnn',
            3,    # message_type: frame buffer update request
            $args->{incremental},
            $args->{x},
            $args->{y},
            $args->{width},
            $args->{height}));
}

# frame buffer update request
sub send_update_request {
    my ($self) = @_;

    # after 2 seconds: send forced update
    # after 4 seconds: turn off screen
    my $time_since_last_update = time - $self->_last_update_received;

    # if there were no updates, send a forced update request
    # to get a defined live sign. If that doesn't help, consider
    # the framebuffer outdated
    if ($self->_framebuffer) {
        if (($self->_vnc_stalled == 1) && ($self->_last_update_requested - $self->_last_update_received > 4)) {
            $self->_last_update_received(0);
            # return black image - screen turned off
            bmwqemu::diag "considering VNC stalled - turning black";
            $self->_framebuffer(tinycv::new($self->width, $self->height));
            $self->_vnc_stalled(2);
        }
        if ($time_since_last_update > 2) {
            $self->send_forced_update_request;
            $self->_vnc_stalled(1) unless $self->_vnc_stalled;
        }
    }

    my $incremental = $self->_framebuffer ? 1 : 0;
    # if we have a black screen, we need a full update
    $incremental = 0 unless $self->_last_update_received;
    return $self->_send_frame_buffer(
        {
            incremental => $incremental,
            x           => 0,
            y           => 0,
            width       => $self->width,
            height      => $self->height
        });
}

# to check if VNC connection is still alive
# just force an update to the upper 16x16 pixels
# to avoid checking old screens if VNC goes down
sub send_forced_update_request {
    my ($self) = @_;

    $self->_last_update_requested(time);
    return $self->_send_frame_buffer(
        {
            incremental => 0,
            x           => 0,
            y           => 0,
            width       => 16,
            height      => 16
        });
}

sub _receive_message {
    my $self = shift;

    my $socket = $self->socket;

    $socket->blocking(0);
    my $ret = $socket->read(my $message_type, 1);
    $socket->blocking(1);

    if (!$ret) {
        return;
    }
    $self->_vnc_stalled(0);

    die "socket closed: $ret\n${\Dumper $self}" unless $ret > 0;

    $message_type = unpack('C', $message_type);
    #print "receive message $message_type\n";

    #<<< tidy off
    # This result is unused.  It's meaning is different for the different methods
    my $result
      = !defined $message_type ? die 'bad message type received'
      : $message_type == 0     ? $self->_receive_update()
      : $message_type == 1     ? $self->_receive_colour_map()
      : $message_type == 2     ? $self->_receive_bell()
      : $message_type == 3     ? $self->_receive_cut_text()
      : $message_type == 0x39  ? $self->_receive_ikvm_session()
      : $message_type == 0x04 ? $self->_discard_ikvm_message($message_type, 20)
      : $message_type == 0x16 ? $self->_discard_ikvm_message($message_type, 1)
      : $message_type == 0x33 ? $self->_discard_ikvm_message($message_type, 4)
      : $message_type == 0x37 ? $self->_discard_ikvm_message($message_type, $self->old_ikvm ? 2 : 3)
      : $message_type == 0x3c ? $self->_discard_ikvm_message($message_type, 8)
      :                         die 'unsupported message type received';
    #>>> tidy on
    return $message_type;
}

sub _receive_update {
    my ($self) = @_;

    $self->_last_update_received(time);
    my $image = $self->_framebuffer;
    if (!$image && $self->width && $self->height) {
        $image = tinycv::new($self->width, $self->height);
        $self->_framebuffer($image);
    }

    my $socket               = $self->socket;
    my $hlen                 = $socket->read(my $header, 3) || die 'unexpected end of data';
    my $number_of_rectangles = unpack('xn', $header);

    #bmwqemu::diag "NOR $number_of_rectangles";

    my $depth = $self->depth;

    my $do_endian_conversion = $self->_do_endian_conversion;

    foreach (1 .. $number_of_rectangles) {
        $socket->read(my $data, 12) || die 'unexpected end of data';
        my ($x, $y, $w, $h, $encoding_type) = unpack 'nnnnN', $data;

        # unsigned -> signed conversion
        $encoding_type = unpack 'l', pack 'L', $encoding_type;

        #bmwqemu::diag "UP $x,$y $w x $h $encoding_type";

        # work around buggy addrlink VNC
        next if ($w * $h == 0);

        my $bytes_per_pixel = $self->_bpp / 8;

        ### Raw encoding ###
        if ($encoding_type == 0 && !$self->ikvm) {

            $socket->read(my $data, $w * $h * $bytes_per_pixel) || die 'unexpected end of data';

            # splat raw pixels into the image
            my $img = tinycv::new($w, $h);

            $image->map_raw_data($data, $x, $y, $w, $h, $self->vncinfo);
        }
        elsif ($encoding_type == 16) {
            $self->_receive_zlre_encoding($x, $y, $w, $h);
        }
        elsif ($encoding_type == -223) {
            $self->width($w);
            $self->height($h);
            $image = tinycv::new($self->width, $self->height);
            $self->_framebuffer($image);
        }
        elsif ($encoding_type == -257) {
            bmwqemu::diag("pointer type $x $y $w $h $encoding_type");
            $self->absolute($x);
        }
        elsif ($encoding_type == -261) {
            my $led_data;
            $socket->read($led_data, 1) || die "unexpected end of data";
            my @bytes = unpack("C", $led_data);
            bmwqemu::diag("led state $bytes[0] $w $h $encoding_type");
        }
        elsif ($self->ikvm) {
            $self->_receive_ikvm_encoding($encoding_type, $x, $y, $w, $h);
        }
        else {
            die 'unsupported update encoding ' . $encoding_type;
        }
    }

    return $number_of_rectangles;
}

sub _discard_ikvm_message {
    my ($self, $type, $bytes) = @_;
    # we don't care for the content
    $self->socket->read(my $dummy, $bytes);
    print "discarding $bytes bytes for message $type\n";

    #   when 0x04
    #     bytes "front-ground-event", 20
    #   when 0x16
    #     bytes "keep-alive-event", 1
    #   when 0x33
    #     bytes "video-get-info", 4
    #   when 0x37
    #     bytes "mouse-get-info", 2
    #   when 0x3c
    #     bytes "get-viewer-lang", 8
}

sub _receive_zlre_encoding {
    my ($self, $x, $y, $w, $h) = @_;

    my $socket = $self->socket;
    my $image  = $self->_framebuffer;

    my $pi = $self->_pixinfo;

    my $stime = time;
    $socket->read(my $data, 4)
      or die "short read for length";
    my ($data_len) = unpack('N', $data);
    my $read_len = 0;
    while ($read_len < $data_len) {
        my $len = read($socket, $data, $data_len - $read_len, $read_len);
        die "short read for zlre data $read_len - $data_len" unless $len;
        $read_len += $len;
    }
    if (time - $stime > 0.1) {
        diag sprintf("read $data_len in %fs\n", time - $stime);
    }
    # the zlib header is only sent once per session
    $self->{_inflater} ||= new Compress::Raw::Zlib::Inflate();
    my $out;
    my $old_total_out = $self->{_inflater}->total_out;
    my $status = $self->{_inflater}->inflate($data, $out, 1);
    if ($status != Z_OK) {
        die "inflation failed $status";
    }
    my $res = $image->map_raw_data_zrle($x, $y, $w, $h, $self->vncinfo, $out, $self->{_inflater}->total_out - $old_total_out);
    die "not read enough data" unless $old_total_out + $res == $self->{_inflater}->total_out;
    return $res;
}

sub _receive_ikvm_encoding {
    my ($self, $encoding_type, $x, $y, $w, $h) = @_;

    my $socket = $self->socket;
    my $image  = $self->_framebuffer;

    # ikvm specific
    $socket->read(my $aten_data, 8);
    my ($data_prefix, $data_len) = unpack('NN', $aten_data);
    #printf "P $encoding_type $data_prefix $data_len $x+$y $w x $h (%dx%d)\n", $self->width, $self->height;

    $self->screen_on($w < 33000);    # screen is off is signaled by negative numbers

    # ikvm doesn't bother sending screen size changes
    if ($w != $self->width || $h != $self->height) {
        if ($self->screen_on) {
            # printf "resizing to $w $h from %dx%d\n", $self->width, $self->height;
            my $newimg = tinycv::new($w, $h);
            if ($image) {
                $image = $image->copyrect(0, 0, min($image->xres(), $w), min($image->yres(), $h));
                $newimg->blend($image, 0, 0);
            }
            $self->width($w);
            $self->height($h);
            $image = $newimg;
            $self->_framebuffer($image);
        }
        else {
            $self->_framebuffer(undef);
        }
        # resync mouse (magic)
        $self->socket->print(pack('Cn', 7, 1920));
    }

    if ($encoding_type == 89) {
        return if $data_len == 0;
        my $required_data = $w * $h * 2;
        my $data;
        print "Additional Bytes: ";
        while ($data_len > $required_data) {
            $socket->read($data, 1) || die "unexpected end of data";
            $data_len--;
            my @bytes = unpack("C", $data);
            printf "%02x ", $bytes[0];
        }
        print "\n";

        $socket->read($data, $required_data);
        my $img = tinycv::new($w, $h);
        $img->map_raw_data_rgb555($data);
        $image->blend($img, $x, $y);
    }
    elsif ($encoding_type == 0) {
        # ikvm manages to redeclare raw to be something completely different ;(
        $socket->read(my $data, 10) || die "unexpected end of data";
        my ($type, $segments, $length) = unpack('CxNN', $data);
        while ($segments--) {
            $socket->read(my $data, 6) || die "unexpected end of data";
            my ($dummy_a, $dummy_b, $y, $x) = unpack('nnCC', $data);
            $socket->read($data, 512) || die "unexpected end of data";
            my $img = tinycv::new(16, 16);
            $img->map_raw_data_rgb555($data);

            if ($x * 16 + $img->xres() > $image->xres()) {
                my $nxres = $image->xres() - $x * 16;
                next if $nxres < 0;
                $img = $img->copyrect(0, 0, $nxres, $img->yres());

            }
            if ($y * 16 + $img->yres() > $image->yres()) {
                my $nyres = $image->yres() - $y * 16;
                next if $nyres < 0;
                $img = $img->copyrect(0, 0, $img->xres(), $nyres);
            }
            $image->blend($img, $x * 16, $y * 16);
        }
    }
    elsif ($encoding_type == 87) {
        return if $data_len == 0;
        if ($self->old_ikvm) {
            die "we guessed wrong - this is a new board!";
        }
        $socket->read(my $data, $data_len);
        # enforce high quality to simplify our decoder
        if (substr($data, 0, 4) ne pack('CCn', 11, 11, 444)) {
            print "fixing quality\n";
            my $template = 'CCCn';
            $self->socket->print(
                pack(
                    $template,
                    0x32,    # message type
                    0,       # magic number
                    11,      # highest possible quality
                    444,     # no sub sampling
                ));
        }
        else {
            $image->map_raw_data_ast2100($data, $data_len);
        }
    }
    else {
        die "unsupported encoding $encoding_type\n";
    }
}

sub _receive_colour_map {
    my $self = shift;

    $self->socket->read(my $map_infos, 5);
    my ($padding, $first_colour, $number_of_colours) = unpack('Cnn', $map_infos);

    for (my $i = 0; $i < $number_of_colours; $i++) {
        $self->socket->read(my $colour, 6);
        my ($red, $green, $blue) = unpack('nnn', $colour);
        tinycv::set_colour($self->vncinfo, $first_colour + $i, $red / 256, $green / 256, $blue / 256);
    }
    #die "we do not support color maps $first_colour $number_of_colours";

    return 1;
}

sub _receive_bell {
    my $self = shift;

    # And discard it...

    return 1;
}

sub _receive_ikvm_session {
    my $self = shift;

    $self->socket->read(my $ikvm_session_infos, 264);

    my ($msg1, $msg2, $str) = unpack('NNZ256', $ikvm_session_infos);
    print "IKVM Session Message: $msg1 $msg2 $str\n";
    return 1;
}

sub _receive_cut_text {
    my $self = shift;

    my $socket = $self->socket;
    $socket->read(my $cut_msg, 7) || die 'unexpected end of data';
    my $cut_length = unpack 'xxxN', $cut_msg;
    $socket->read(my $cut_string, $cut_length)
      || die 'unexpected end of data';

    # And discard it...

    return 1;
}

sub mouse_move_to {
    my ($self, $x, $y) = @_;
    $self->send_pointer_event(0, $x, $y);
}

sub mouse_click {
    my ($self, $x, $y) = @_;

    $self->send_pointer_event(1, $x, $y);
    $self->send_pointer_event(0, $x, $y);
}

sub mouse_right_click {
    my ($self, $x, $y) = @_;

    $self->send_pointer_event(4, $x, $y);
    $self->send_pointer_event(0, $x, $y);
}

1;

__END__


=head1 AUTHORS

Leon Brocard acme@astray.com

Chris Dolan clotho@cpan.org

Apple Remote Desktop authentication based on LibVNCServer

Maurice Castro maurice@ipexchange.com.au

Many thanks for Foxtons Ltd for giving Leon the opportunity to write
the original version of this module.

Copyright (C) 2006, Leon Brocard

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.

Copyright (C) 2014, Stephan Kulow (coolo@suse.de) 
adapted to be purely useful for qemu/openqa

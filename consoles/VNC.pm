# créé par ansible pour la gestion du clavier fr
## penser à ajouter dans les variables openQA : VNCKB=fr

package consoles::VNC;

use Mojo::Base -base, -signatures;
use bytes;
use Feature::Compat::Try;
use IO::Socket::INET;
use bmwqemu qw(diag fctwarn);
use Time::HiRes qw( sleep gettimeofday time );
use List::Util 'min';
use Crypt::DES;
use Compress::Raw::Zlib;
use Carp qw(confess cluck carp croak);
use Data::Dumper 'Dumper';
use Scalar::Util 'blessed';
use Encode;
use OpenQA::Exceptions;
use consoles::VMWare;

has [qw(description hostname port username password socket name width height depth
      no_endian_conversion  _pixinfo _colourmap _framebuffer _rfb_version screen_on
      _bpp _true_colour _do_endian_conversion absolute ikvm keymap _last_update_received
      _last_update_requested check_vnc_stalls _vnc_stalled vncinfo old_ikvm dell
      vmware_vnc_over_ws_url original_hostname)];

our $VERSION = '0.40';

my $MAX_PROTOCOL_VERSION = '003.008';
my $MAX_PROTOCOL_HANDSHAKE = 'RFB ' . $MAX_PROTOCOL_VERSION . chr(0x0a);    # Max version supported

# This line comes from perlport.pod
my $client_is_big_endian = unpack('h*', pack('s', 1)) =~ /01/ ? 1 : 0;

# The numbers in the hashes below were acquired from the VNC source code
my %supported_depths = (
    32 => {    # same as 24 actually
        bpp => 32,
        true_colour => 1,
        red_max => 255,
        green_max => 255,
        blue_max => 255,
        red_shift => 16,
        green_shift => 8,
        blue_shift => 0,
    },
    24 => {
        bpp => 32,
        true_colour => 1,
        red_max => 255,
        green_max => 255,
        blue_max => 255,
        red_shift => 16,
        green_shift => 8,
        blue_shift => 0,
    },
    16 => {    # same as 15
        bpp => 16,
        true_colour => 1,
        red_max => 31,
        green_max => 31,
        blue_max => 31,
        red_shift => 10,
        green_shift => 5,
        blue_shift => 0,
    },
    15 => {
        bpp => 16,
        true_colour => 1,
        red_max => 31,
        green_max => 31,
        blue_max => 31,
        red_shift => 10,
        green_shift => 5,
        blue_shift => 0
    },
    8 => {
        bpp => 8,
        true_colour => 0,
        red_max => 8,
        green_max => 8,
        blue_max => 4,
        red_shift => 5,
        green_shift => 2,
        blue_shift => 0,
    },
);

my @encodings = (

    # These ones are defined in rfbproto.pdf
    {
        num => 0,
        name => 'Raw',
        supported => 1,
    },
    {
        num => 16,
        name => 'ZRLE',
        supported => 1,
    },
    {
        num => -223,
        name => 'DesktopSize',
        supported => 1,
    },
    {
        num => -257,
        name => 'VNC_ENCODING_POINTER_TYPE_CHANGE',
        supported => 1,
    },
    {
        num => -261,
        name => 'VNC_ENCODING_LED_STATE',
        supported => 1,
    },
    {
        num => -224,
        name => 'VNC_ENCODING_LAST_RECT',
        supported => 1,
    },
);

sub login ($self, $connect_timeout = undef, $timeout = undef) {
    consoles::VMWare::setup_for_vnc_console($self);

    # arbitrary
    my $connect_failure_limit = 2;

    $self->width(0);
    $self->height(0);
    $self->screen_on(1);
    # in a land far far before our time
    $self->_last_update_received(0);
    $self->_last_update_requested(0);
    $self->_vnc_stalled(0);
    $self->check_vnc_stalls(!$self->ikvm);
    $self->{_inflater} = undef;

    my $hostname = $self->hostname || 'localhost';
    my $port = $self->port || 5900;
    my $description = $self->description || 'VNC server';
    my $is_local = $hostname =~ qr/(localhost|127\.0\.0\.\d+|::1)/;
    my $local_timeout = $bmwqemu::vars{VNC_TIMEOUT_LOCAL} // 60;
    my $remote_timeout = $bmwqemu::vars{VNC_TIMEOUT_REMOTE} // 60;
    my $local_connect_timeout = $bmwqemu::vars{VNC_CONNECT_TIMEOUT_LOCAL} // 20;
    my $remote_connect_timeout = $bmwqemu::vars{VNC_CONNECT_TIMEOUT_REMOTE} // 240;
    $connect_timeout //= $is_local ? $local_connect_timeout : $remote_connect_timeout;
    $timeout //= $is_local ? $local_timeout : $remote_timeout;

    my $socket;
    my $err_cnt = 0;
    my $endtime = time + $connect_timeout;
    while (!$socket) {
        $socket = IO::Socket::INET->new(PeerAddr => $hostname, PeerPort => $port, Proto => 'tcp', Timeout => $timeout);
        if (!$socket) {
            $err_cnt++;
            my $error_message = "Error connecting to $description <$hostname:$port>: $@";
            OpenQA::Exception::VNCSetupError->throw(error => $error_message) if time > $endtime;
            # we might be too fast trying to connect to the VNC host (e.g.
            # qemu) so ignore the first occurrences of a failed
            # connection attempt.
            bmwqemu::fctwarn($error_message) if $err_cnt > $connect_failure_limit;
            sleep 1;
            next;
        }
        $socket->sockopt(Socket::TCP_NODELAY, 1);    # turn off Naegle's algorithm for vnc

        # set timeout for receiving/sending as the timeout specified via c'tor only applies to connect/accept
        # note: Using native code to set VNC socket timeout because from C++ we can simply include `struct timeval`
        #       from `#include <sys/time.h>` instead of relying on unportable manual packing.
        tinycv::set_socket_timeout($socket->fileno, $timeout) or bmwqemu::fctwarn "Unable to set VNC socket timeout: $!";
    }
    $self->socket($socket);

    try {
        $self->_handshake_protocol_version();
        $self->_handshake_security();
        $self->_client_initialization();
        $self->_server_initialization();
    }
    catch ($e) {
        # clean up so socket can be garbage collected
        $self->socket(undef);
        die $e;
    }
    return undef;
}

sub _handshake_protocol_version ($self) {
    my $socket = $self->socket;
    $socket->read(my $protocol_version, 12) || die 'unexpected end of data';
    my $protocol_pattern = qr/\A RFB [ ] (\d{3}\.\d{3}) \s* \z/xms;
    die 'Malformed RFB protocol: ' . $protocol_version if $protocol_version !~ m/$protocol_pattern/xms;
    $self->_rfb_version($1);

    if ($protocol_version gt $MAX_PROTOCOL_HANDSHAKE) {
        $protocol_version = $MAX_PROTOCOL_HANDSHAKE;
        # Repeat with the changed version
        $self->_rfb_version($MAX_PROTOCOL_VERSION);
    }

    die 'RFB protocols earlier than v3.3 are not supported' if $self->_rfb_version lt '003.003';

    # let's use the same version of the protocol, or the max, whichever's lower
    $socket->print($protocol_version);
}

sub _handshake_security ($self) {
    my $socket = $self->socket;

    # Retrieve list of security options
    my $security_type;
    if ($self->_rfb_version ge '003.007') {
        my $number_of_security_types = 0;
        my $r = $socket->read($number_of_security_types, 1);
        $number_of_security_types = unpack('C', $number_of_security_types) if $r;
        die 'Error authenticating' if $number_of_security_types == 0;

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
        $socket->print(pack('C', 1)) if $self->_rfb_version ge '003.007';
    }
    elsif ($security_type == 2) {
        # DES-encrypted challenge/response

        $socket->print(pack('C', 2)) if $self->_rfb_version ge '003.007';

        # # VNC authentication is to be used and protocol data is to be
        # # sent unencrypted. The server sends a random 16-byte
        # # challenge:

        # # No. of bytes Type [Value] Description
        # # 16 U8 challenge

        $socket->read(my $challenge, 16) || die 'unexpected end of data';

        # the RFB protocol only uses the first 8 characters of a password
        my $key = substr($self->password, 0, 8);
        $key = '' unless defined $key;
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

        $socket->print(pack('C', 16));    # accept
        $socket->write(pack('Z24', $self->username));
        $socket->write(pack('Z24', $self->password));
        $socket->read(my $num_tunnels, 4);

        $num_tunnels = unpack('N', $num_tunnels);
        # found in https://github.com/kanaka/noVNC
        $self->old_ikvm($num_tunnels > 0x1000000 ? 1 : 0);
        $socket->read(my $ikvm_session, 20) || die 'unexpected end of data';
        my @bytes = unpack("C20", $ikvm_session);
        print "Session info: ";
        for my $byte (@bytes) {
            printf "%02x ", $byte;
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
        die 'Failed to login' unless $security_result == 0;
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

sub _client_initialization ($self) {
    my $socket = $self->socket;
    $socket->print(pack('C', !$self->ikvm));    # share
}

sub _server_initialization ($self) {
    my $socket = $self->socket;
    $socket->read(my $server_init, 24) || die 'unexpected end of data';

    my ($framebuffer_width, $framebuffer_height,
        $bits_per_pixel, $depth, $server_is_big_endian, $true_colour_flag,
        %pixinfo,
        $name_length);
    ($framebuffer_width, $framebuffer_height,
        $bits_per_pixel, $depth, $server_is_big_endian, $true_colour_flag,
        $pixinfo{red_max}, $pixinfo{green_max}, $pixinfo{blue_max},
        $pixinfo{red_shift}, $pixinfo{green_shift}, $pixinfo{blue_shift},
        $name_length
    ) = unpack 'nnCCCCnnnCCCxxxN', $server_init;

    if (!$self->depth) {

        # client did not express a depth preference, so check if the server's preference is OK
        die 'Unsupported depth ' . $depth unless $supported_depths{$depth};
        die 'Unsupported bits-per-pixel value ' . $bits_per_pixel unless $bits_per_pixel == $supported_depths{$depth}->{bpp};
        die 'Unsupported true colour flag' if ($true_colour_flag ? !$supported_depths{$depth}->{true_colour} : $supported_depths{$depth}->{true_colour});
        $self->depth($depth);

        # Use server's values for *_max and *_shift

    }
    elsif ($depth != $self->depth) {
        for my $key (qw(red_max green_max blue_max red_shift green_shift blue_shift)) {
            $pixinfo{$key} = $supported_depths{$self->depth}->{$key};
        }
    }
    $self->absolute($self->ikvm // 0);

    $self->width($framebuffer_width) if !$self->width && !$self->ikvm;
    $self->height($framebuffer_height) if !$self->height && !$self->ikvm;
    $self->_pixinfo(\%pixinfo);
    $self->_bpp($supported_depths{$self->depth}->{bpp});
    $self->_true_colour($supported_depths{$self->depth}->{true_colour});
    $self->_do_endian_conversion($self->no_endian_conversion ? 0 : ($server_is_big_endian && $client_is_big_endian));

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
        $self->_do_endian_conversion, $self->_true_colour, $self->_bpp / 8, $pixinfo{red_max}, $pixinfo{red_shift},
        $pixinfo{green_max}, $pixinfo{green_shift}, $pixinfo{blue_max}, $pixinfo{blue_shift});
    $self->vncinfo($info);

    # setpixelformat
    $socket->print(
        pack(
            'CCCCCCCCnnnCCCCCC',
            0,    # message_type
            0,    # padding
            0,    # padding
            0,    # padding
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
            0,    # padding
            0,    # padding
            0,    # padding
        ));

    # set encodings

    my @encs = grep { $_->{supported} } @encodings;

    # Prefer the higher-numbered encodings
    @encs = reverse sort { $a->{num} <=> $b->{num} } @encs;

    if ($self->dell) {
        # idrac's ZRLE implementation even kills tigervnc, they duplicate
        # frames under certain conditions. Raw works ok
        @encs = grep { $_->{name} ne 'ZRLE' } @encs;
    }
    $socket->print(
        pack(
            'CCn',
            2,    # message_type
            0,    # padding
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

sub _send_key_event ($self, $down_flag, $key) {
    # A key press or release. Down-flag is non-zero (true) if the key is now pressed, zero
    # (false) if it is now released. The key itself is specified using the "keysym" values
    # defined by the X Window System.

    my $socket = $self->socket;
    my $template = 'CCnN';
    # for a strange reason ikvm has a lot more padding
    $template = 'CxCnNx9' if $self->ikvm;
    $socket->print(
        pack(
            $template,
            4,    # message_type
            $down_flag,    # down-flag
            0,    # padding
            $key,    # key
        ));
}

sub send_key_event_down ($self, $key) { $self->_send_key_event(1, $key) }

sub send_key_event_up ($self, $key) { $self->_send_key_event(0, $key) }

## no critic (HashKeyQuotes)

my $keymap_x11 = {
    'esc' => 0xff1b,
    'down' => 0xff54,
    'right' => 0xff53,
    'up' => 0xff52,
    'left' => 0xff51,
    'equal' => ord('='),
    'spc' => ord(' '),
    'minus' => ord('-'),
    'shift' => 0xffe1,
    'ctrl' => 0xffe3,    # left, right is e4
    'ctrlright' => 0xffe4,    
    'caps' => 0xffe5,
    'meta' => 0xffe7,    # left, right is e8
    'metaright' => 0xffe8,    
    'alt' => 0xffe9,    # left one, right is ea
    'altgr' => 0xffea, 
    'ret' => 0xff0d,
    'tab' => 0xff09,
    'backspace' => 0xff08,
    'end' => 0xff57,
    'delete' => 0xffff,
    'home' => 0xff50,
    'insert' => 0xff63,
    'pgup' => 0xff55,
    'pgdn' => 0xff56,
    'sysrq' => 0xff15,
    'super' => 0xffeb,    # left, right is ec
    'superright' => 0xffec, 
};

# ikvm aka USB: https://www.win.tue.nl/~aeb/linux/kbd/scancodes-14.html
my $keymap_ikvm = {
    'ctrl' => 0xe0,
    'shift' => 0xe1,
    'alt' => 0xe2,
    'meta' => 0xe3,
    'caps' => 0x39,
    'sysrq' => 0x9a,
    'end' => 0x4d,
    'delete' => 0x4c,
    'home' => 0x4a,
    'insert' => 0x49,
    'super' => 0xe3,

    #    {NSPrintScreenFunctionKey, 0x46},
    # {NSScrollLockFunctionKey, 0x47},
    # {NSPauseFunctionKey, 0x48},

    'pgup' => 0x4b,
    'pgdn' => 0x4e,

    'left' => 0x50,
    'right' => 0x4f,
    'up' => 0x52,
    'down' => 0x51,

    '0' => 0x27,
    'ret' => 0x28,
    'esc' => 0x29,
    'backspace' => 0x2a,
    'tab' => 0x2b,
    ' ' => 0x2c,
    'spc' => 0x2c,
    'minus' => 0x2d,
    '=' => 0x2e,
    '[' => 0x2f,
    ']' => 0x30,
    '\\' => 0x31,
    ';' => 0x33,
    '\'' => 0x34,
    '`' => 0x35,
    ',' => 0x36,
    '.' => 0x37,
    '/' => 0x38,
};

sub shift_keys () {
    # see http://en.wikipedia.org/wiki/IBM_PC_keyboard
    # see https://www.tcl.tk/man/tcl8.4/TkCmd/keysyms.html
    # see https://www.ascii-code.com/fr
    # see https://doc.ubuntu-fr.org/tutoriel/comprendre_la_configuration_du_clavier

    return {
        '1' => '&',
        '2' => chr(233), # é est mal encodé donc on le désigne par chr(233)
        '3' => '"',
        '4' => '\'',
        '5' => '(',
        '6' => '-',
        '7' => chr(232), # è est mal encodé donc on le désigne par chr(232)
        '8' => '_',
        '9' => chr(231), # ç est mal encodé donc on le désigne par chr(231)
	'0' => chr(224), # à est mal encodé donc on le désigne par chr(224)
        #'°' => ')',
        chr(176) => ')', # ° est parfois mal encodé donc on le désigne par chr(176)
	'+' => '=',
	
	# second line
	#'"' => '^', # trema buggué car boucle avec les double quote
	#'£' => '$',
	chr(163) => '$', # £ est parfois mal encodé donc on le désigne par chr(163)

        # third line
	'%' => chr(249), # ù est mal encodé donc on le désigne par chr(249)
	#'µ' => '*',
	chr(181) => '*', # µ est parfois mal encodé donc on le désigne par chr(181)

        # fourth line
	'?' => ',',
	'.' => ';',
	'/' => ':',
	#'§' => '!',
	chr(167) => '!', # § est parfois mal encodé donc on le désigne par chr(167)
 	'>' => '<',
    };
}

sub special_keys () {
    # see https://www.tcl.tk/man/tcl8.4/TkCmd/keysyms.html
    # see https://www.ascii-code.com/fr
    # see https://doc.ubuntu-fr.org/tutoriel/comprendre_la_configuration_du_clavier
    # Liste des caractères mal encodés (ASCII vs UTF8) : °çéèà§µù || mal gérés par qemu (altgr)
    return {
        chr(233) => '2', # ord('é')=233 # é est mal encodé donc on prend le caractère 2 qui est sur la même touche
        '~' => '2', # ~ est keysym no scancode in qemu donc on prend le caractère 2 qui est sur la même touche
	'#' => '3', # '#' keysym = 35 : no scancode in qemu
        '{' => '\'', # '{' keysym no scancode in qemu
        '[' => '(', # '[' keysym no scancode in qemu
        '|' => '-', # '|' keysym no scancode in qemu
        '`' => '7', # ` keysym no scancode in qemu donc on prend le caractère 7 qui est sur la même touche
        chr(232) => '7', # ord('è')=232 # è est mal encodé donc on prend le caractère 7 qui est sur la même touche
        '\\' => '_', # '\' keysym no scancode in qemu
        chr(231) => '9', # ord('ç')=231 # ç est mal encodé donc on prend le caractère 9 qui est sur la même touche
        '^' => '9', # ^ est mal encodé donc on prend le caractère 9 qui est sur la même touche
        chr(224) => '0', # ord('à')=224 # à est mal encodé donc on prend le caractère 0 qui est sur la même touche
        '@' => '0', # @ keysym no scancode in qemu donc on prend le caractère 0 qui est sur la même touche
        chr(176) => ')', # ord('°')=176 # '°' est mal encodé donc on le désigne par chr(176) et on prend le caractère ')' qui est sur la même touche
        ']' => ')', # ']' keysym no scancode in qemu
        '}' => '=', # '}' keysym no scancode in qemu
        chr(249) => '%', # ord('ù')=249 # ù est mal encodé donc on prend le caractère % qui est sur la même touche
        chr(181) => '*', # ord('µ')=181 # µ est mal encodé donc on prend le caractère * qui est sur la même touche
	chr(167) => '!', # ord('§')=167 # § est mal encodé donc on prend le caractère ! qui est sur la même touche
    }
}

sub altgr_keys () {
    # see http://en.wikipedia.org/wiki/IBM_PC_keyboard
    # see https://www.tcl.tk/man/tcl8.4/TkCmd/keysyms.html
    # see https://www.ascii-code.com/fr
    # see https://doc.ubuntu-fr.org/tutoriel/comprendre_la_configuration_du_clavier
    return {
        '~' => chr(233), # é est mal encodé donc on le désigne par chr(233)
        '#' => '"',
        '{' => '\'',
        '[' => '(',
        '|' => '-',
        '`' => chr(232), # è est mal encodé donc on le désigne par chr(232)
        '\\' => '_',
        '^' => chr(231), # ç est mal encodé donc on le désigne par chr(231)
        '@' => chr(224), # à est mal encodé donc on le désigne par chr(224)
        ']' => ')',
	'}' => '=',
	#chr(164) => '$', # ¤ commenté car apparaît avec ê à la place... # ¤ est mal encodé donc on le désigne par chr(164)
	#chr(183) => ':', # · semble non supporté ou accessible via une autre combinaison (shift+altgr+k) # · est mal encodé donc on le désigne par char(183)
	chr(128) => 'e', # € est mal encodé donc on le désigne par char(128)

    };
}
## use critic

sub die_on_invalid_mapping ($key) {
    #die decode_utf8 "No map for '$key' - layouts other than en-us are not supported\n";
    die "No map for '$key' - layouts other than fr are not supported\n";
}

sub init_x11_keymap ($self) {
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
        bmwqemu::diag "[Keytab Shift Keys] $key : [$keymap{shift}, ".ord(uc $key)."]";
        # shift-H looks strange, but that's how VNC works
        $keymap{uc $key} = [$keymap{shift}, ord(uc $key)];
    }
    # VNC doesn't use the unshifted values, only prepends a shift key
    for my $key (keys %{shift_keys()}) {
        die_on_invalid_mapping($key) unless $keymap{$key};
	bmwqemu::diag "[Keytab Shift Keys] $key : [$keymap{shift},$keymap{$key}]";
        $keymap{$key} = [$keymap{shift}, $keymap{$key}];
    }
    my %altgrkeys=%{altgr_keys()};
    for my $key (keys (%altgrkeys)) {
       die_on_invalid_mapping($key) unless $keymap{$key};
	bmwqemu::diag "[Keytab Altgr Keys] $key : [$keymap{altgr},$keymap{$altgrkeys{$key}}]";
        $keymap{$key} = [$keymap{altgr}, $keymap{$altgrkeys{$key}}];
    }
    my %specialkeys=%{special_keys()};
    for my $key (keys (%specialkeys)) {
        die_on_invalid_mapping($key) unless $keymap{$key};
        if (ref($keymap{$key}) eq 'ARRAY') {
	    if (ref($keymap{$specialkeys{$key}}) eq 'ARRAY') {
		$keymap{$key}[-1] = $keymap{$specialkeys{$key}}[-1];
	    }
	    else {
		$keymap{$key}[-1] = $keymap{$specialkeys{$key}};
	    }
	    bmwqemu::diag "[Keytab Special Keys] $key : @{$keymap{$key}}";
	}
	else {
	    if (ref($keymap{$specialkeys{$key}}) eq 'ARRAY') {
                $keymap{$key} = $keymap{$specialkeys{$key}}[-1];
            }
            else {
                $keymap{$key} = $keymap{$specialkeys{$key}};
            }
	    bmwqemu::diag "[Keytab Special Keys] $key : $keymap{$key}";
	}
    }
    $self->keymap(\%keymap);
    foreach my $k (keys(%keymap)) {
    	bmwqemu::diag "[Keytab] Key=Char=$k Val=Keysym=$keymap{$k}";
    }

}

sub init_ikvm_keymap ($self) {
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
        die_on_invalid_mapping($key) unless $keymap{$shift};
        $keymap{$key} = [$keymap{shift}, $keymap{$shift}];
    }

    $self->keymap(\%keymap);
}


sub map_and_send_key ($self, $keys, $down_flag, $press_release_delay) {
    die "need delay" unless $press_release_delay;

    if ($self->ikvm) {
        $self->init_ikvm_keymap;
    }
    else {
        $self->init_x11_keymap;
    }

    my @events;

    # Caractère non décodé en UTF8
    #bmwqemu::diag "[String] $keys";

    for my $key (split('-', $keys)) {
	$key = decode_utf8($key);
	#bmwqemu::diag "[ENCODING UTF8] key $key, decoded key ".encode("utf-8", $key)." defini ? :".defined($self->keymap->{$key});
	#bmwqemu::diag "[ENCODING UTF16] key $key, decoded key ".encode("utf-16", $key)." defini ? :".defined($self->keymap->{$key});
	#bmwqemu::diag "[ENCODING LATIN1] key $key, decoded key ".encode("latin-1", $key)." defini ? :".defined($self->keymap->{$key});
	#bmwqemu::diag "[ENCODING ISO885915] key $key, decoded key ".encode("iso-8859-15", $key)." defini ? :".defined($self->keymap->{$key});
	
	# Caractère décodé en UTF8
        #bmwqemu::diag decode_utf8("[Char] $key (defini dans le keytab ? 1=oui : ".defined($self->keymap->{$key}.")"));

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
            die_on_invalid_mapping($key);
        }
    }

    if ($self->ikvm && @events == 1) {
        $self->_send_key_event(2, $events[0]);
        return;
    }

    if (!defined $down_flag || $down_flag == 1) {
        for my $key (@events) {
            $self->send_key_event_down($key);
            sleep($press_release_delay);
        }
    }
    if (!defined $down_flag || $down_flag == 0) {
        for my $key (reverse @events) {
            $self->send_key_event_up($key);
            sleep($press_release_delay);
        }
    }
}

sub send_pointer_event ($self, $button_mask, $x, $y) {
    bmwqemu::diag "send_pointer_event $button_mask, $x, $y, " . $self->absolute;

    my $template = 'CCnn';
    $template = 'CxCnnx11' if ($self->ikvm);

    $self->socket->print(
        pack(
            $template,
            5,    # message type
            $button_mask,    # button-mask
            $x,    # x-position
            $y,    # y-position
        ));
}

# drain the VNC socket from all pending incoming messages
# return truthy value if there was a screen update
sub update_framebuffer ($self) {
    my $have_recieved_update = 0;
    try {
        local $SIG{__DIE__} = undef;
        while (defined(my $message_type = $self->_receive_message())) {
            $have_recieved_update = 1 if $message_type == 0;
        }
    }
    catch ($e) {
        die $e unless blessed $e && $e->isa('OpenQA::Exception::VNCProtocolError');
        bmwqemu::fctwarn "Error in VNC protocol - relogin: " . $e->error;
        $self->login;
    }
    return $have_recieved_update;
}

use POSIX ':errno_h';

sub _send_frame_buffer ($self, $args) {
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
sub send_update_request ($self, $incremental = undef) {
    my $time_after_vnc_is_considered_stalled = $bmwqemu::vars{VNC_STALL_THRESHOLD} // 4;
    # after 2 seconds: send forced update
    # after 4 seconds: turn off screen
    my $time_since_last_update = time - $self->_last_update_received;

    # if there were no updates, send a forced update request
    # to get a defined live sign. If that doesn't help, reconnect
    if ($self->_framebuffer && $self->check_vnc_stalls) {
        if ($self->_vnc_stalled && $time_since_last_update > $time_after_vnc_is_considered_stalled) {
            $self->_last_update_received(0);
            # return black image - screen turned off
            bmwqemu::diag sprintf("considering VNC stalled, no update for %.2f seconds", $time_since_last_update);
            $self->socket->close;
            $self->socket(undef);
            return $self->login;
        }
        if ($time_since_last_update > 2) {
            $self->send_forced_update_request;
            $self->_vnc_stalled(1) unless $self->_vnc_stalled;
        }
    }

    # if we have a black screen, we need a full update
    $incremental = $self->_framebuffer && $self->_last_update_received ? 1 : 0 unless defined $incremental;
    return $self->_send_frame_buffer(
        {
            incremental => $incremental,
            x => 0,
            y => 0,
            width => $self->width,
            height => $self->height
        });
}

# to check if VNC connection is still alive
# just force an update to the upper 16x16 pixels
# to avoid checking old screens if VNC goes down
sub send_forced_update_request ($self) {
    $self->_last_update_requested(time);
    return $self->_send_frame_buffer(
        {
            incremental => 0,
            x => 0,
            y => 0,
            width => 16,
            height => 16
        });
}

sub _receive_message ($self) {
    my $socket = $self->socket;
    $socket or die 'socket does not exist. Probably your backend instance could not start or died.';
    $socket->blocking(0);
    my $ret = $socket->read(my $message_type, 1);
    $socket->blocking(1);
    return unless $ret;
    $self->_vnc_stalled(0);

    die "socket closed: $ret\n${\Dumper $self}" unless $ret > 0;

    $message_type = unpack('C', $message_type);

    # This result is unused.  It's meaning is different for the different methods
    my $result
      = !defined $message_type ? die 'bad message type received'
      : $message_type == 0 ? $self->_receive_update()
      : $message_type == 1 ? $self->_receive_colour_map()
      : $message_type == 2 ? $self->_receive_bell()
      : $message_type == 3 ? $self->_receive_cut_text()
      : $message_type == 0x39 ? $self->_receive_ikvm_session()
      : $message_type == 0x04 ? $self->_discard_ikvm_message($message_type, 20)
      : $message_type == 0x16 ? $self->_discard_ikvm_message($message_type, 1)
      : $message_type == 0x33 ? $self->_discard_ikvm_message($message_type, 4)
      : $message_type == 0x37 ? $self->_discard_ikvm_message($message_type, $self->old_ikvm ? 2 : 3)
      : $message_type == 0x3c ? $self->_discard_ikvm_message($message_type, 8)
      : die 'unsupported message type received';
    return $message_type;
}

sub _receive_update ($self) {
    $self->_last_update_received(time);
    my $image = $self->_framebuffer;
    if (!$image && $self->width && $self->height) {
        $image = tinycv::new($self->width, $self->height);
        $self->_framebuffer($image);
    }

    my $socket = $self->socket;
    $socket->read(my $header, 3) || die 'unexpected end of data';

    my $number_of_rectangles = unpack('xn', $header);
    foreach (my $i = 0; $i < $number_of_rectangles; ++$i) {
        $socket->read(my $data, 12) || die 'unexpected end of data';
        my ($x, $y, $w, $h, $encoding_type) = unpack 'nnnnN', $data;

        # unsigned -> signed conversion
        $encoding_type = unpack 'l', pack 'L', $encoding_type;

        # work around buggy addrlink VNC
        next if $encoding_type > 0 && $w * $h == 0;

        if ($encoding_type == 0 && !$self->ikvm) {    # Raw
            $socket->read(my $data, $w * $h * $self->_bpp / 8) || die 'unexpected end of data';
            $image->map_raw_data($data, $x, $y, $w, $h, $self->vncinfo);
        }
        elsif ($encoding_type == 16) {    # ZRLE
            $self->_receive_zrle_encoding($x, $y, $w, $h);
        }
        elsif ($encoding_type == -223) {    # DesktopSize pseudo-encoding
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
            # 100     CapsLock is on, NumLock and ScrollLock are off
            # 010     NumLock is on, CapsLock and ScrollLock are off
            # 111     CapsLock, NumLock and ScrollLock are on
            bmwqemu::diag("led state $bytes[0] $w $h $encoding_type");
        }
        elsif ($encoding_type == -224) {
            last;
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

sub _discard_ikvm_message ($self, $type, $bytes) {
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

sub _receive_zrle_encoding ($self, $x, $y, $w, $h) {
    my $socket = $self->socket;
    my $image = $self->_framebuffer;

    my $pi = $self->_pixinfo;

    my $stime = time;
    $socket->read(my $data, 4)
      or OpenQA::Exception::VNCProtocolError->throw(error => 'short read for length');
    my ($data_len) = unpack('N', $data);
    my $read_len = 0;
    while ($read_len < $data_len) {
        my $len = read($socket, $data, $data_len - $read_len, $read_len);
        OpenQA::Exception::VNCProtocolError->throw(error => "short read for zrle data $read_len - $data_len") unless $len;
        $read_len += $len;
    }
    diag sprintf("read $data_len in %fs\n", time - $stime) if (time - $stime > 0.1);
    # the zlib header is only sent once per session
    $self->{_inflater} ||= Compress::Raw::Zlib::Inflate->new;
    my $out;
    my $old_total_out = $self->{_inflater}->total_out;
    my $status = $self->{_inflater}->inflate($data, $out, 1);
    OpenQA::Exception::VNCProtocolError->throw(error => "inflation failed $status") unless $status == Z_OK;
    my $res = $image->map_raw_data_zrle($x, $y, $w, $h, $self->vncinfo, $out, $self->{_inflater}->total_out - $old_total_out);
    OpenQA::Exception::VNCProtocolError->throw(error => "not read enough data") if $old_total_out + $res != $self->{_inflater}->total_out;
    return $res;
}

sub _receive_ikvm_encoding ($self, $encoding_type, $x, $y, $w, $h) {
    my $socket = $self->socket;
    my $image = $self->_framebuffer;

    # ikvm specific
    $socket->read(my $aten_data, 8);
    my ($data_prefix, $data_len) = unpack('NN', $aten_data);

    $self->screen_on($w < 33000);    # screen is off is signaled by negative numbers

    # ikvm doesn't bother sending screen size changes
    if ($w != $self->width || $h != $self->height) {
        if ($self->screen_on) {
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
            $socket->read($data, 1) || OpenQA::Exception::VNCProtocolError->throw(error => "unexpected end of data");
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
        $socket->read(my $data, 10) || OpenQA::Exception::VNCProtocolError->throw(error => "unexpected end of data");
        my ($type, $segments, $length) = unpack('CxNN', $data);
        while ($segments--) {
            $socket->read(my $data, 6) || OpenQA::Exception::VNCProtocolError->throw(error => "unexpected end of data");
            my ($dummy_a, $dummy_b, $y, $x) = unpack('nnCC', $data);
            $socket->read($data, 512) || OpenQA::Exception::VNCProtocolError->throw(error => "unexpected end of data");
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
        die "we guessed wrong - this is a new board!" if $self->old_ikvm;
        $socket->read(my $data, $data_len);
        # enforce high quality to simplify our decoder
        if (substr($data, 0, 4) ne pack('CCn', 11, 11, 444)) {
            print "fixing quality\n";
            my $template = 'CCCn';
            $self->socket->print(
                pack(
                    $template,
                    0x32,    # message type
                    0,    # magic number
                    11,    # highest possible quality
                    444,    # no sub sampling
                ));
        }
        else {
            $image->map_raw_data_ast2100($data, $data_len);
        }
    }
    else {
        die "unsupported encoding $encoding_type";
    }
}

sub _receive_colour_map ($self) {
    $self->socket->read(my $map_infos, 5);
    my ($padding, $first_colour, $number_of_colours) = unpack('Cnn', $map_infos);

    for (0 .. $number_of_colours - 1) {
        $self->socket->read(my $colour, 6);
        my ($red, $green, $blue) = unpack('nnn', $colour);
        tinycv::set_colour($self->vncinfo, $first_colour + $_, $red / 256, $green / 256, $blue / 256);
    }
    return 1;
}

# Discard the bell signal
sub _receive_bell ($self) { 1 }

sub _receive_ikvm_session ($self) {
    $self->socket->read(my $ikvm_session_infos, 264);

    my ($msg1, $msg2, $str) = unpack('NNZ256', $ikvm_session_infos);
    print "IKVM Session Message: $msg1 $msg2 $str\n";
    return 1;
}

sub _receive_cut_text ($self) {
    my $socket = $self->socket;
    $socket->read(my $cut_msg, 7) || OpenQA::Exception::VNCProtocolError->throw(error => 'unexpected end of data');
    my $cut_length = unpack 'xxxN', $cut_msg;
    $socket->read(my $cut_string, $cut_length)
      || OpenQA::Exception::VNCProtocolError->throw(error => 'unexpected end of data');

    # And discard it...

    return 1;
}

sub mouse_move_to ($self, $x, $y) {
    $self->send_pointer_event(0, $x, $y);
}

sub mouse_click ($self, $x, $y) {
    $self->send_pointer_event(1, $x, $y);
    $self->send_pointer_event(0, $x, $y);
}

sub mouse_right_click ($self, $x, $y) {
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

Copyright 2006, Leon Brocard

Copyright 2014-2017 Stephan Kulow (coolo@suse.de)
adapted to be purely useful for qemu/openqa

Copyright 2017-2021 SUSE LLC

SPDX-License-Identifier: Artistic-1.0 OR GPL-1.0-or-later

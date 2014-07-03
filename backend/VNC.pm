package backend::VNC;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);
use Crypt::DES;
use IO::Socket::INET;
use bytes;
use bmwqemu qw(diag);

__PACKAGE__->mk_accessors(
    qw(hostname port username password socket name width height depth save_bandwidth
      hide_cursor server_endian
      _pixinfo _colourmap _framebuffer _cursordata _rfb_version
      _bpp _true_colour _big_endian _image_format
      )
);
our $VERSION = '0.40';

my $MAX_PROTOCOL_VERSION = 'RFB 003.008' . chr(0x0a);  # Max version supported

# This line comes from perlport.pod
my $AM_BIG_ENDIAN = unpack( 'h*', pack( 's', 1 ) ) =~ /01/ ? 1 : 0;

# The numbers in the hashes below were acquired from the VNC source code
my %supported_depths = (
    '24' => {
        bpp         => 32,
        true_colour => 1,
        red_max     => 255,
        green_max   => 255,
        blue_max    => 255,
        red_shift   => 16,
        green_shift => 8,
        blue_shift  => 0,
    },
    '16' => {
        bpp         => 16,
        true_colour => 1,
        red_max     => 31,
        green_max   => 31,
        blue_max    => 31,
        red_shift   => 10,
        green_shift => 5,
        blue_shift  => 0,
    },
    '8' => {
        bpp         => 8,
        true_colour => 0,
        red_max     => 255,
        green_max   => 255,
        blue_max    => 255,
        red_shift   => 16,
        green_shift => 8,
        blue_shift  => 0,
    },

    # Unused right now, but supportable
    '8t' => {
        bpp         => 8,
        true_colour => 1,    #!!!
        red_max     => 7,
        green_max   => 7,
        blue_max    => 3,
        red_shift   => 0,
        green_shift => 3,
        blue_shift  => 6,
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
        num       => 1,
        name      => 'CopyRect',
        supported => 1,
    },
    {
        num       => 2,
        name      => 'RRE',
        supported => 1,
    },
    {
        num       => 4,
        name      => 'CoRRE',
        supported => 1,
    },
    {
        num       => 5,
        name      => 'Hextile',
        supported => 1,
        bandwidth => 1,
    },
    {
        num       => 16,
        name      => 'ZRLE',
        supported => 0,
        bandwidth => 1,
    },
    {
        num       => -239,
        name      => 'Cursor',
        supported => 1,
        cursor    => 1,
    },
    {
        num       => -223,
        name      => 'DesktopSize',
        supported => 1,
    },

    # Learned about these from cvs://cotvnc.sf.net/cotvnc/Source/rfbproto.h
    # None of them are currently used
    map( {
            {
                num       => -256 + $_,
                name      => 'CompressLevel' . $_,
                supported => 0,
                compress  => 1,
            }
        } 0 .. 9 ),
    {
        num       => -240,
        name      => 'XCursor',
        supported => 0,
        cursor    => 1,
    },
    {
        num       => -224,
        name      => 'LastRect',
        supported => 0,
    },
    map( {
            {
                num       => -32 + $_,
                name      => 'QualityLevel' . $_,
                supported => 0,
                quality   => 1,
            }
        } 0 .. 9 ),

    # Learned about this one from pyvnc2swf/rfb.py, but I don't understand where it comes from
    # It doesn't seem to be documented in CotVNC or VNC 4.1.1 source code
    {
        num       => -232,
        name      => 'CursorPos',
        supported => 1,
        cursor    => 1,
    },
);

sub list_encodings {
    my $pkg_or_self = shift;

    my %encmap = map { $_->{num} => $_->{name} } @encodings;
    return %encmap;
}

sub login {
    my $self     = shift;
    my $hostname = $self->hostname;
    my $port     = $self->port;
    my $socket   = IO::Socket::INET->new(
        PeerAddr => $hostname || 'localhost',
        PeerPort => $port     || '5900',
        Proto    => 'tcp',
    ) || die "Error connecting to $hostname: $@";
    $socket->timeout(15);
    $self->socket($socket);

    eval {
        $self->_handshake_protocol_version();
        $self->_handshake_security();
        $self->_client_initialization();
        $self->_server_initialization();
    };
    my $error = $@;    # store so it doesn't get overwritten
    if ($error) {

        # clean up so socket can be garbage collected
        $self->socket(undef);
        die $error;
    }
}

sub _handshake_protocol_version {
    my $self = shift;

    my $socket = $self->socket;
    $socket->read( my $protocol_version, 12 ) || die 'unexpected end of data';

    bmwqemu::diag "prot: $protocol_version";

    my $protocol_pattern = qr/\A RFB [ ] (\d{3}\.\d{3}) \s* \z/xms;
    if ( $protocol_version !~ m/$protocol_pattern/xms ) {
        die 'Malformed RFB protocol: ' . $protocol_version;
    }
    $self->_rfb_version($1);

    if ( $protocol_version gt $MAX_PROTOCOL_VERSION ) {
        $protocol_version = $MAX_PROTOCOL_VERSION;

        # Repeat with the changed version
        if ( $protocol_version !~ m/$protocol_pattern/xms ) {
            die 'Malformed RFB protocol';
        }
        $self->_rfb_version($1);
    }

    if ( $self->_rfb_version lt '003.003' ) {
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
    if ( $self->_rfb_version ge '003.007' ) {
        $socket->read( my $number_of_security_types, 1 )
          || die 'unexpected end of data';
        $number_of_security_types = unpack( 'C', $number_of_security_types );

        bmwqemu::diag "types: $number_of_security_types";

        if ( $number_of_security_types == 0 ) {
            die 'Error authenticating';
        }

        my @security_types;
        foreach ( 1 .. $number_of_security_types ) {
            $socket->read( my $security_type, 1 )
              || die 'unexpected end of data';
            $security_type = unpack( 'C', $security_type );

            #        bmwqemu::diag "sec: $security_type";
            push @security_types, $security_type;
        }

        my @pref_types = ( 1, 2 );
        @pref_types = ( 30, 1, 2 ) if $self->username;

        for my $preferred_type (@pref_types) {
            if ( 0 < grep { $_ == $preferred_type } @security_types ) {
                $security_type = $preferred_type;
                last;
            }
        }
    }
    else {

        # In RFB 3.3, the server dictates the security type
        $socket->read( $security_type, 4 ) || die 'unexpected end of data';
        $security_type = unpack( 'N', $security_type );
    }

    if ( !$security_type ) {

        die 'Connection failed';

    }
    elsif ( $security_type == 2 ) {

        # DES-encrypted challenge/response

        if ( $self->_rfb_version ge '003.007' ) {
            $socket->print( pack( 'C', 2 ) );
        }

        $socket->read( my $challenge, 16 ) || die 'unexpected end of data';

        #    bmwqemu::diag "chal: " . unpack('h*', $challenge) . "\n";

        # the RFB protocol only uses the first 8 characters of a password
        my $key = substr( $self->password, 0, 8 );
        $key = '' if ( !defined $key );
        $key .= pack( 'C', 0 ) until ( length($key) % 8 ) == 0;

        my $realkey;

        #    bmwqemu::diag unpack('b*', $key);
        foreach my $byte ( split //, $key ) {
            $realkey .= pack( 'b8', scalar reverse unpack( 'b8', $byte ) );
        }

        #    bmwqemu::diag unpack('b*', $realkey);

        my $cipher = Crypt::DES->new($realkey);
        my $response;
        my $i = 0;
        while ( $i < 16 ) {
            my $word = substr( $challenge, $i, 8 );

            #        bmwqemu::diag "$i: " . length($word);
            $response .= $cipher->encrypt($word);
            $i += 8;
        }

        #    bmwqemu::diag "resp: " . unpack('h*', $response) . "\n";

        $socket->print($response);

    }
    elsif ( $security_type == 1 ) {

        # No authorization needed!
        if ( $self->_rfb_version ge '003.007' ) {
            $socket->print( pack( 'C', 1 ) );
        }

    }
    elsif ( $security_type == 30 ) {

        require Crypt::GCrypt::MPI;
        require Crypt::Random;

        # ARD - Apple Remote Desktop - authentication
        $socket->print( pack( 'C', 30 ) );    # use ARD
        $socket->read( my $gen, 2 ) || die 'unexpected end of data';
        $socket->read( my $len, 2 ) || die 'unexpected end of data';
        my $keylen = $self->_bin_int($len);
        $socket->read( my $mod,  $keylen ) || die 'unexpected end of data';
        $socket->read( my $resp, $keylen ) || die 'unexpected end of data';

        my $genmpi = Crypt::GCrypt::MPI::new(
            secure => 0,
            value  => $self->_bin_int($gen),
            format => Crypt::GCrypt::MPI::FMT_USG()
        );
        my $modmpi = Crypt::GCrypt::MPI::new(
            secure => 0,
            value  => $mod,
            format => Crypt::GCrypt::MPI::FMT_USG()
        );
        my $respmpi = Crypt::GCrypt::MPI::new(
            secure => 0,
            value  => $resp,
            format => Crypt::GCrypt::MPI::FMT_USG()
        );
        my $privmpi = $self->_mpi_randomize($keylen);

        my $pubmpi = $genmpi->copy()->powm( $privmpi, $modmpi );
        my $keympi = $respmpi->copy()->powm( $privmpi, $modmpi );
        my $pub = $self->_mpi_2_bytes( $pubmpi, $keylen );
        my $key = $self->_mpi_2_bytes( $keympi, $keylen );
        my $md5 = Crypt::GCrypt->new( type => 'digest', algorithm => 'md5' );
        $md5->write($key);
        my $shared  = $md5->read();
        my $passlen = length( $self->password ) + 1;
        my $userlen = length( $self->username ) + 1;
        $passlen = 64 if ( $passlen > 64 );
        my $passpad = 64 - $passlen;
        $userlen = 64 if ( $userlen > 64 );
        my $userpad = 64 - $userlen;
        my $up      = Crypt::Random::makerandom_octet(
            Length   => $userpad,
            Strength => 1
        );
        my $pp = Crypt::Random::makerandom_octet(
            Length   => $passpad,
            Strength => 1
        );
        my $userpass = pack "a*xa*a*xa*", $self->username, $up,$self->password, $pp;
        my $aes = Crypt::GCrypt->new(
            type      => 'cipher',
            algorithm => 'aes',
            mode      => 'ecb'
        );
        $aes->start('encrypting');
        $aes->setkey($shared);
        my $cyptxt = $aes->encrypt($userpass);
        $cyptxt .= $aes->finish;
        $socket->write( $cyptxt, 128 );  # appears to be only writing 16 bytes
        $socket->write( $pub, $keylen ); # appears to be only writing 16 bytes
        $socket->read( my $security_result, 4 )
          || die 'unexpected end of data';
        $security_result = $self->_bin_int($security_result);

        if ( $security_result == 1 ) {
            $socket->read( my $len, 4 ) || die 'unexpected end of data';
            $socket->read( my $msg, $self->_bin_int($len) )
              || die 'unexpected end of data';
            die "VNC Authentication Failed: $msg";
        }
        elsif ( $security_result == 2 ) {

            # too many
            die "VNC Authentication Failed - too many tries";
        }
    }
    else {

        die "no supported vnc authentication mechanism";

    }

    # the RFB protocol always returns a result for type 2,
    # but type 1, only for 003.008 and up
    if ( ( $self->_rfb_version ge '003.008' && $security_type == 1 )
        || $security_type == 2 )
    {
        $socket->read( my $security_result, 4 )
          || die 'unexpected end of data';
        $security_result = unpack( 'I', $security_result );

        #    bmwqemu::diag $security_result;
        die 'login failed' if $security_result;
    }
    elsif ( !$socket->connected ) {
        die 'login failed';
    }
}

sub _mpi_randomize {
    my ( $self, $l ) = @_;
    my $bits  = int( $l / 8 ) * 8;
    my $bytes = int( $bits / 8 );
    my $r= Crypt::Random::makerandom_octet( Length => $bytes, Strength => 1 );
    my @ra = unpack( "C*", $r );
    my $mpi = Crypt::GCrypt::MPI::new( secure => 0, value => 0 );
    my $tfs = Crypt::GCrypt::MPI::new( secure => 0, value => 256 );
    for ( my $i = 0; $i < $bytes; $i++ ) {
        $mpi = $mpi->mul($tfs);
        my $n = $ra[$i];
        $mpi = $mpi->add(Crypt::GCrypt::MPI::new( secure => 0, value => $n ) );
    }
    return $mpi;
}

sub _mpi_2_bytes {
    my ( $self, $mpi, $sz ) = @_;
    my $s   = $mpi->print( Crypt::GCrypt::MPI::FMT_USG() );
    my $pad = $sz - length($s);
    return pack( "x[$pad]a*", $s );
}

sub _bin_int {
    my ( $self, $s ) = @_;
    my @a = unpack( "C*", $s );
    my $r = 0;
    for ( my $i = 0; $i < @a; $i++ ) {
        $r = 256 * $r;
        $r += $a[$i];
    }
    return $r;
}

sub _client_initialization {
    my $self = shift;

    my $socket = $self->socket;

    $socket->print( pack( 'C', 1 ) );    # share
}

sub _server_initialization {
    my $self = shift;

    my $socket = $self->socket;
    $socket->read( my $server_init, 24 ) || die 'unexpected end of data';

    my ( $framebuffer_width, $framebuffer_height, $bits_per_pixel, $depth,$big_endian_flag, $true_colour_flag, %pixinfo, $name_length );
    (   $framebuffer_width,  $framebuffer_height,   $bits_per_pixel,$depth,              $big_endian_flag,      $true_colour_flag,$pixinfo{red_max},   $pixinfo{green_max},   $pixinfo{blue_max},$pixinfo{red_shift}, $pixinfo{green_shift}, $pixinfo{blue_shift},$name_length) = unpack 'nnCCCCnnnCCCxxxN', $server_init;

    bmwqemu::diag "FW $framebuffer_width x $framebuffer_height";

    bmwqemu::diag "$bits_per_pixel bpp / depth $depth / $big_endian_flag be / $true_colour_flag tc / $pixinfo{red_max},$pixinfo{green_max},$pixinfo{blue_max} / $pixinfo{red_shift},$pixinfo{green_shift},$pixinfo{blue_shift}";

    bmwqemu::diag $name_length;

    if ( !$self->depth ) {

        # client did not express a depth preference, so check if the server's preference is OK
        if ( !$supported_depths{$depth} ) {
            die 'Unsupported depth ' . $depth;
        }
        if ( $bits_per_pixel != $supported_depths{$depth}->{bpp} ) {
            die 'Unsupported bits-per-pixel value ' . $bits_per_pixel;
        }
        if (
            $true_colour_flag
            ? !$supported_depths{$depth}->{true_colour}
            : $supported_depths{$depth}->{true_colour}
          )
        {
            die 'Unsupported true colour flag';
        }
        $self->depth($depth);

        # Use server's values for *_max and *_shift

    }
    elsif ( $depth != $self->depth ) {
        for my $key (qw(red_max green_max blue_max red_shift green_shift blue_shift)){
            $pixinfo{$key} = $supported_depths{ $self->depth }->{$key};
        }
    }

    if ( !$self->width ) {
        $self->width($framebuffer_width);
    }
    if ( !$self->height ) {
        $self->height($framebuffer_height);
    }
    $self->_pixinfo( \%pixinfo );
    $self->_bpp( $supported_depths{ $self->depth }->{bpp} );
    $self->_true_colour( $supported_depths{ $self->depth }->{true_colour} );
    $self->_big_endian($self->server_endian ? $big_endian_flag : $AM_BIG_ENDIAN );

    $socket->read( my $name_string, $name_length )
      || die 'unexpected end of data';
    $self->name($name_string);

    #    warn $name_string;

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
            $self->_big_endian,
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
        )
    );

    # set encodings

    my @encs = grep { $_->{supported} } @encodings;

    # Prefer the higher-numbered encodings
    @encs = reverse sort { $a->{num} <=> $b->{num} } @encs;

    if ( !$self->save_bandwidth ) {
        @encs = grep { !$_->{bandwidth} } @encs;
    }
    if ( $self->hide_cursor ) {
        @encs = grep { !$_->{cursor} } @encs;
    }

    $socket->print(
        pack(
            'CCn',
            2,               # message_type
            0,               # padding
            scalar @encs,    # number_of_encodings
        )
    );
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

sub capture {
    my $self   = shift;
    my $socket = $self->socket;

    $self->{need_update} = 1;
    $self->_send_update_request();
    while ( ( my $message_type = $self->_receive_message() ) == 0 ) {
        bmwqemu::diag "MT $message_type\n";
        last unless ($self->{need_update});
    }

    return $self->_image_plus_cursor;
}

sub _image_plus_cursor {
    my $self = shift;

    my $image  = $self->_framebuffer;
    my $cursor = $self->_cursordata;
    if (  !$self->hide_cursor
        && $cursor
        && $cursor->{image}
        && defined $cursor->{x} )
    {

        #$cursor->{image}->save('cursor.png'); # temporary -- debugging
        $image= $image->clone(); # make a duplicate so we can overlay the cursor
        $image->blend(
            $cursor->{image},
            1,                 # don't modify destination alpha
            0, 0, $cursor->{width}, $cursor->{height},    # source dimensions
            $cursor->{x}, $cursor->{y}, $cursor->{width},
            $cursor->{height},    # destination dimensions
        );
    }
    return $image;
}

sub _send_key_event {
    my ( $self, $down_flag, $key ) = @_;

    # A key press or release. Down-flag is non-zero (true) if the key is now pressed, zero
    # (false) if it is now released. The key itself is specified using the “keysym” values
    # defined by the X Window System.

    my $socket = $self->socket;
    $socket->print(
        pack(
            'CCnN',
            4,             # message_type
            $down_flag,    # down-flag
            0,             # padding
            $key,          # key
        )
    );
}

sub send_key_event_down {
    my ( $self, $key ) = @_;
    $self->_send_key_event( 1, $key );
}

sub send_key_event_up {
    my ( $self, $key ) = @_;
    $self->_send_key_event( 0, $key );
}

sub send_key_event {
    my ( $self, $key ) = @_;
    $self->send_key_event_down($key);
    $self->send_key_event_up($key);
}

sub send_key_event_string {
    my ( $self, $string ) = @_;
    foreach my $key ( map {ord} split //, $string ) {
        warn $key;
        $self->send_key_event($key);
    }
}

sub send_pointer_event {
    my ( $self, $button_mask, $x, $y ) = @_;

    $self->socket->print(
        pack(
            'CCnn',
            5,               # message type
            $button_mask,    # button-mask
            $x,              # x-position
            $y,              # y-position
        )
    );
}

sub _send_update_request {
    my $self = shift;

    # frame buffer update request
    my $socket = $self->socket;
    my $incremental = $self->_framebuffer ? 1 : 0;
    $socket->print(
        pack(
            'CCnnnn',
            3,               # message_type
            $incremental,    # incremental
            0,               # x
            0,               # y
            $self->width,
            $self->height,
        )
    );
}

sub _receive_message {
    my $self = shift;

    my $socket = $self->socket;
    $socket->read( my $message_type, 1 ) || die 'unexpected end of data';
    $message_type = unpack( 'C', $message_type );

    bmwqemu::diag("RM $message_type");

    # This result is unused.  It's meaning is different for the different methods
    my $result=
        !defined $message_type ? die 'bad message type received'
      : $message_type == 0     ? $self->_receive_update()
      : $message_type == 1     ? $self->_receive_colour_map()
      : $message_type == 2     ? $self->_receive_bell()
      : $message_type == 3     ? $self->_receive_cut_text()
      :                          die 'unsupported message type received';

    return $message_type;
}

sub _receive_update {
    my $self = shift;

    my $image = $self->_framebuffer;
    if ( !$image ) {
        #        $self->_framebuffer( $image
        #                = Image::Imlib2->new( $self->width, $self->height ) );
        if ( $self->_image_format ) {
            $image->image_set_format( $self->_image_format );
        }
        # We're going to be splatting pixels, so make sure every pixel is opaque
        #$image->set_colour( 0, 0, 0, 255 );
        #$image->fill_rectangle( 0, 0, $self->width, $self->height );
    }

    my $socket = $self->socket;
    my $hlen = $socket->read( my $header, 3 ) || die 'unexpected end of data';
    my $number_of_rectangles = unpack( 'xn', $header );

    bmwqemu::diag "NOR $hlen - $number_of_rectangles";

    my $depth = $self->depth;

    my $big_endian = $self->_big_endian;
    my $read_and_set_colour=
      $depth == 24
      ? (
        $big_endian
        ? \&_read_and_set_colour_24_be
        : \&_read_and_set_colour_24_le
      )
      : $depth == 16 ? (
        $big_endian
        ? \&_read_and_set_colour_16_be
        : \&_read_and_set_colour_16_le
      )
      : $depth == 8 ? \&_read_and_set_colour_8
      :               die 'unsupported depth';

    foreach ( 1 .. $number_of_rectangles ) {
        $socket->read( my $data, 12 ) || die 'unexpected end of data';
        my ( $x, $y, $w, $h, $encoding_type ) = unpack 'nnnnN', $data;

        # unsigned -> signed conversion
        $encoding_type = unpack 'l', pack 'L', $encoding_type;

        bmwqemu::diag "$x,$y $w x $h $encoding_type";

        ### Raw encoding ###
        if ( $encoding_type == 0 ) {

            $self->{need_update} = 0;
            if ( $depth == 24 && $AM_BIG_ENDIAN == $self->_big_endian ){

                # Performance boost: splat raw pixels into the image
                $socket->read( my $data, $w * $h * 4 );
                #                my $raw = Image::Imlib2->new_using_data( $w, $h, $data );
                #                $raw->has_alpha(0);
                #                $image->blend( $raw, 0, 0, 0, $w, $h, $x, $y, $w, $h );

            }
            else {

                for my $py ( $y .. $y + $h - 1 ) {
                    for my $px ( $x .. $x + $w - 1 ) {
                        $self->$read_and_set_colour();
                        #$image->draw_point( $px, $py );
                    }
                }

            }

            ### CopyRect encooding ###
        }
        elsif ( $encoding_type == 1 ) {

            $socket->read( my $srcpos, 4 ) || die 'unexpected end of data';
            my ( $srcx, $srcy ) = unpack 'nn', $srcpos;

            #my $copy = $image->crop( $srcx, $srcy, $w, $h );
            #$image->blend( $copy, 0, 0, 0, $w, $h, $x, $y, $w, $h );

            ### RRE and CoRRE encodings ###
        }
        elsif ( $encoding_type == 2 || $encoding_type == 4 ) {

            $socket->read( my $num_sub_rects, 4 )
              || die 'unexpected end of data';
            $num_sub_rects = unpack 'N', $num_sub_rects;

            $self->$read_and_set_colour();
            #$image->fill_rectangle( $x, $y, $w, $h );

            # RRE is U16, CoRRE is U8
            my $geombytes = $encoding_type == 2 ? 8      : 4;
            my $format    = $encoding_type == 2 ? 'nnnn' : 'CCCC';

            for my $i ( 1 .. $num_sub_rects ) {

                $self->$read_and_set_colour();
                $socket->read( my $subrect, $geombytes )
                  || die 'unexpected end of data';
                my ( $sx, $sy, $sw, $sh ) = unpack $format, $subrect;
                $image->fill_rectangle( $x + $sx, $y + $sy, $sw, $sh );

            }

            ### Hextile encoding ###
        }
        elsif ( $encoding_type == 5 ) {

            my $maxx = $x + $w;
            my $maxy = $y + $h;
            my $background;
            my $foreground;

            # Step over 16x16 tiles in the target rectangle
            for ( my $ry = $y; $ry < $maxy; $ry += 16 ) {
                my $rh = $maxy - $ry > 16 ? 16 : $maxy - $ry;
                for ( my $rx = $x; $rx < $maxx; $rx += 16 ) {
                    my $rw = $maxx - $rx > 16 ? 16 : $maxx - $rx;
                    $socket->read( my $mask, 1 )
                      || die 'unexpected end of data';
                    $mask = unpack 'C', $mask;

                    if ( $mask & 0x1 ) {    # Raw tile
                        for my $py ( $ry .. $ry + $rh - 1 ) {
                            for my $px ( $rx .. $rx + $rw - 1 ) {
                                $self->$read_and_set_colour();
                                $image->draw_point( $px, $py );
                            }
                        }

                    }
                    else {

                        if ( $mask & 0x2 ) {    # background set
                            $background = $self->$read_and_set_colour();
                        }
                        if ( $mask & 0x4 ) {    # foreground set
                            $foreground = $self->$read_and_set_colour();
                        }
                        if ( $mask & 0x8 ) {    # has subrects

                            $socket->read( my $nsubrects, 1 )
                              || die 'unexpected end of data';
                            $nsubrects = unpack 'C', $nsubrects;

                            if ( !$mask & 0x10 ) {    # use foreground colour
                                $image->set_colour( @{$foreground} );
                            }
                            for my $i ( 1 .. $nsubrects ) {
                                if ( $mask & 0x10 ) { # use per-subrect colour
                                    $self->$read_and_set_colour();
                                }
                                $socket->read( my $pos, 1 )
                                  || die 'unexpected end of data';
                                $pos = unpack 'C', $pos;
                                $socket->read( my $size, 1 )
                                  || die 'unexpected end of data';
                                $size = unpack 'C', $size;
                                my $sx = $pos >> 4;
                                my $sy = $pos & 0xff;
                                my $sw = 1 + ( $size >> 4 );
                                my $sh = 1 + ( $size & 0xff );
                                $image->fill_rectangle( $rx + $sx, $ry + $sy,$sw, $sh );
                            }

                        }
                        else {    # no subrects
                            $image->set_colour( @{$background} );
                            $image->fill_rectangle( $rx, $ry, $rw, $rh );
                        }
                    }
                }
            }

            ### Cursor ###
        }
        elsif ( $encoding_type == -239 ) {

            # realvnc 3.3 sends empty cursor messages, so skip
            next unless $w || $h;

            my $cursordata = $self->_cursordata;
            if ( !$cursordata ) {
                $self->_cursordata( $cursordata = {} );
            }
            #            $cursordata->{image}    = Image::Imlib2->new( $w, $h );
            $cursordata->{hotspotx} = $x;
            $cursordata->{hotspoty} = $y;
            $cursordata->{width}    = $w;
            $cursordata->{height}   = $h;

            my $cursor = $cursordata->{image}
              || die "Failed to create cursor buffer $w x $h";
            $cursor->has_alpha(1);

            my @pixbuf;
            for my $i ( 1 .. $w * $h ) {
                push @pixbuf, $self->$read_and_set_colour();
            }
            my $masksize    = int( ( $w + 7 ) / 8 ) * $h;
            my $maskrowsize = int( ( $w + 7 ) / 8 ) * 8;
            $socket->read( my $mask, $masksize )
              || die 'unexpected end of data';
            $mask = unpack 'B*', $mask;

            #print "masksize: $masksize\n";
            #print "maskrowsize: $maskrowsize\n";
            #print "mask: $mask\n";

            #open my $fh, '>', $ENV{HOME}.'/Desktop/cursor.txt';
            $cursor->will_blend(0);
            for my $cy ( 0 .. $h - 1 ) {
                for my $cx ( 0 .. $w - 1 ) {
                    my $pixel = shift @pixbuf;
                    $pixel || die 'not enough pixels';
                    if ( !substr( $mask, $cx + $cy * $maskrowsize, 1 ) ) {
                        @{$pixel} = ( 0, 0, 0, 0 );
                    }

                    #print "$cx, $cy: @$pixel\n";
                    #print $fh "$cx, $cy: @$pixel\n";
                    $cursor->set_colour( @{$pixel} );
                    $cursor->draw_point( $cx, $cy );
                }
            }
            $cursor->will_blend(1);

            #$cursor->save('vnccursor.png');
            #print "wrote cursor\n";

            ### CursorPos ###
        }
        elsif ( $encoding_type == -232 ) {

            my $cursordata = $self->_cursordata;
            if ( !$cursordata ) {
                $self->_cursordata( $cursordata = {} );
            }
            $cursordata->{x} = $x;
            $cursordata->{y} = $y;

            #print "Cursor pos: $x, $y\n";

        }
        elsif ( $encoding_type == -223 ) {
            $self->width($w);
            $self->height($h);
            # $image->resize...
        }
        elsif ( $encoding_type == 255 ) { # MSG_QEMU
        }
        else {
            die 'unsupported update encoding ' . $encoding_type;
        }
    }

    return $number_of_rectangles;
}

sub _read_and_set_colour_8 {
    my $self = shift;

    $self->socket->read( my $pixel, 1 ) || die 'unexpected end of data';

    my $colours = $self->_colourmap;
    my $index   = unpack( 'C', $pixel );
    my $colour  = $colours->[$index];
    my @colour  = ( $colour->{r}, $colour->{g}, $colour->{b}, 255 );
    $self->_framebuffer->set_colour(@colour);

    return \@colour;
}

sub _read_and_set_colour_16_le {
    my $self = shift;

    $self->socket->read( my $pixel, 2 ) || die 'unexpected end of data';
    my $colour = unpack 'v', $pixel;
    my @colour = (( $colour >> 10 & 31 ) << 3,( $colour >> 5 & 31 ) << 3,( $colour & 31 ) << 3, 255);
    $self->_framebuffer->set_colour(@colour);

    return \@colour;
}

sub _read_and_set_colour_16_be {
    my $self = shift;

    $self->socket->read( my $pixel, 2 ) || die 'unexpected end of data';
    my $colour = unpack 'n', $pixel;
    my @colour = (( $colour >> 10 & 31 ) << 3,( $colour >> 5 & 31 ) << 3,( $colour & 31 ) << 3, 255);
    $self->_framebuffer->set_colour(@colour);

    return \@colour;
}

sub _read_and_set_colour_24_le {
    my $self = shift;

    $self->socket->read( my $pixel, 4 ) || die 'unexpected end of data';
    my $colour = unpack 'V', $pixel;
    my @colour= ( $colour >> 16 & 255, $colour >> 8 & 255, $colour & 255, 255, );
    $self->_framebuffer->set_colour(@colour);

    return \@colour;
}

sub _read_and_set_colour_24_be {
    my $self = shift;

    $self->socket->read( my $pixel, 4 ) || die 'unexpected end of data';
    my $colour = unpack 'N', $pixel;
    my @colour= ( $colour >> 16 & 255, $colour >> 8 & 255, $colour & 255, 255, );
    $self->_framebuffer->set_colour(@colour);

    return \@colour;
}

# The following is the full version that supports all 8, 16, and 32
# bpp and arbitrary pixel formats.  This version is only used when one
# of the faster functions declared above cannot be used due to
# specific VNC settings.

sub _read_and_set_colour {
    my $self  = shift;
    my $pixel = shift;

    my $colours         = $self->_colourmap;
    my $bytes_per_pixel = $self->_bpp / 8;
    if ( !$pixel ) {
        $self->socket->read( $pixel, $bytes_per_pixel )
          || die 'unexpected end of data';
    }
    my @colour;
    if ($colours) {    # indexed colour, depth is 8
        my $index = unpack( 'C', $pixel );
        my $colour = $colours->[$index];
        @colour = ( $colour->{r}, $colour->{g}, $colour->{b}, 255 );
    }
    else {           # true colour, depth is 24 or 16
        my $pixinfo = $self->_pixinfo;
        my $format=
            $bytes_per_pixel == 4 ? ( $self->_big_endian ? 'N' : 'V' )
          : $bytes_per_pixel == 2 ? ( $self->_big_endian ? 'n' : 'v' )
          :                         die 'Unsupported bits-per-pixel value';
        my $colour = unpack $format, $pixel;
        my $r = $colour >> $pixinfo->{red_shift} & $pixinfo->{red_max};
        my $g = $colour >> $pixinfo->{green_shift} & $pixinfo->{green_max};
        my $b = $colour >> $pixinfo->{blue_shift} & $pixinfo->{blue_max};
        if ( $bytes_per_pixel == 4 ) {
            @colour = ( $r, $g, $b, 255 );
        }
        else {
            @colour = ($r * 255 / $pixinfo->{red_max},$g * 255 / $pixinfo->{green_max},$b * 255 / $pixinfo->{blue_max}, 255);
        }
    }
    $self->_framebuffer->set_colour(@colour);
    return \@colour;
}

sub _receive_colour_map {
    my $self = shift;

    # set colour map entries
    my $socket = $self->socket;
    $socket->read( my $padding,      1 ) || die 'unexpected end of data';
    $socket->read( my $first_colour, 2 ) || die 'unexpected end of data';
    $first_colour = unpack( 'n', $first_colour );
    $socket->read( my $number_of_colours, 2 ) || die 'unexpected end of data';
    $number_of_colours = unpack( 'n', $number_of_colours );

    #    warn "colours: $first_colour.. ($number_of_colours)";

    my @colours;
    foreach my $i ( $first_colour .. $first_colour + $number_of_colours - 1 ){
        $socket->read( my $r, 2 ) || die 'unexpected end of data';
        $r = unpack( 'n', $r );
        $socket->read( my $g, 2 ) || die 'unexpected end of data';
        $g = unpack( 'n', $g );
        $socket->read( my $b, 2 ) || die 'unexpected end of data';
        $b = unpack( 'n', $b );

        #        warn "$i $r/$g/$b";

        # The 8-bit colours are in the top byte of each field
        $colours[$i] = { r => $r >> 8, g => $g >> 8, b => $b >> 8 };
    }
    $self->_colourmap( \@colours );
    return 1;
}

sub _receive_bell {
    my $self = shift;

    # And discard it...

    return 1;
}

sub _receive_cut_text {
    my $self = shift;

    my $socket = $self->socket;
    $socket->read( my $cut_msg, 7 ) || die 'unexpected end of data';
    my $cut_length = unpack 'xxxN', $cut_msg;
    $socket->read( my $cut_string, $cut_length )
      || die 'unexpected end of data';

    # And discard it...

    return 1;
}

sub mouse_move_to {
    my ( $self, $x, $y ) = @_;
    $self->send_pointer_event( 0, $x, $y );

    my $cursordata = $self->_cursordata;
    if ( !$cursordata ) {
        $self->_cursordata( $cursordata = {} );
    }
    $cursordata->{x} = $x;
    $cursordata->{y} = $y;
}

sub mouse_click {
    my ($self) = @_;

    my $cursordata = $self->_cursordata;
    if ( !$cursordata ) {
        $self->_cursordata( $cursordata = { x => 0, y => 0 } );
    }

    $self->send_pointer_event( 1, $cursordata->{x}, $cursordata->{y} );
    $self->send_pointer_event( 0, $cursordata->{x}, $cursordata->{y} );
}

sub mouse_right_click {
    my ($self) = @_;

    my $cursordata = $self->_cursordata;
    if ( !$cursordata ) {
        $self->_cursordata( $cursordata = { x => 0, y => 0 } );
    }

    $self->send_pointer_event( 4, $cursordata->{x}, $cursordata->{y} );
    $self->send_pointer_event( 0, $cursordata->{x}, $cursordata->{y} );
}

1;

__END__

=head1 NAME

Net::VNC - A simple VNC client

=head1 SYNOPSIS
    
  use Net::VNC;

  my $vnc = Net::VNC->new({hostname => $hostname, password => $password});
  $vnc->depth(24);
  $vnc->login;

  print $vnc->name . ": " . $vnc->width . ' x ' . $vnc->height . "\n";

  my $image = $vnc->capture;
  $image->save("out.png");

=head1 DESCRIPTION

Virtual Network Computing (VNC) is a desktop sharing system which uses
the RFB (Remote FrameBuffer) protocol to remotely control another
computer. This module acts as a VNC client and communicates to a VNC
server using the RFB protocol, allowing you to capture the screen of
the remote computer.

This module dies upon connection errors (with a timeout of 15 seconds)
and protocol errors.

This implementation is based largely on the RFB Protocol
Specification, L<http://www.realvnc.com/docs/rfbproto.pdf>.  That
document has an error in the DES encryption description, which is
clarified via L<http://www.vidarholen.net/contents/junk/vnc.html>.

=head1 METHODS

=head2 new

The constructor. Given a hostname and a password returns a L<Net::VNC> object:

  my $vnc = Net::VNC->new({hostname => $hostname, password => $password});

Optionally, you can also specify a port, which defaults to 5900. For ARD
(Apple Remote Desktop) authentication you must also specify a username.
You must also install Crypt::GCrypt::MPI and Crypt::Random.

=head2 login

Logs into the remote computer:

  $vnc->login;

=head2 name

Returns the name of the remote computer:

  print $vnc->name . ": " . $vnc->width . ' x ' . $vnc->height . "\n";

=head2 width

Returns the width of the remote screen:

  print $vnc->name . ": " . $vnc->width . ' x ' . $vnc->height . "\n";

=head2 height

Returns the height of the remote screen:

  print $vnc->name . ": " . $vnc->width . ' x ' . $vnc->height . "\n";

=head2 capture

Captures the screen of the remote computer, returning an L<Image::Imlib2> object:

  my $image = $vnc->capture;
  $image->save("out.png");

You may call capture() multiple times.  Each time, the C<$image>
buffer is overwritten with the updated screen.  So, to create a
series of ten screen shots:

  for my $n (1..10) {
    my $filename = sprintf 'snapshot%02d.png', $n++;
    $vnc->capture()->save($filename);
    print "Wrote $filename\n";
  }

=head2 depth

Specify the bit depth for the screen.  The supported choices are 24,
16 or 8.  If unspecified, the server's default value is used.  This
property should be set before the call to login().

=head2 save_bandwidth

Accepts a boolean, defaults to false.  Specifies whether to use more
CPU-intensive algorithms to compress the VNC datastream.  LAN or
localhost connections may prefer to leave this false.  This property
should be set before the call to login().

=head2 list_encodings

Returns a list of encoding number/encoding name pairs.  This can be used as a class method like so:

   my %encodings = Net::VNC->list_encodings();

=head2 send_key_event_down

Send a key down event. The keys are the same as the
corresponding ASCII value. Other common keys:

  BackSpace 0xff08
  Tab 0xff09
  Return or Enter 0xff0d
  Escape 0xff1b
  Insert 0xff63
  Delete 0xffff
  Home 0xff50
  End 0xff57
  Page Up 0xff55
  Page Down 0xff56
  Left 0xff51
  Up 0xff52
  Right 0xff53
  Down 0xff54
  F1 0xffbe
  F2 0xffbf
  F3 0xffc0
  F4 0xffc1
  ... ...
  F12 0xffc9
  Shift (left) 0xffe1
  Shift (right) 0xffe2
  Control (left) 0xffe3
  Control (right) 0xffe4
  Meta (left) 0xffe7
  Meta (right) 0xffe8
  Alt (left) 0xffe9
  Alt (right) 0xffea

  $vnc->send_key_event_down('A');

=head2 send_key_event_up

Send a key up event:

  $vnc->send_key_event_up('A');

=head2 send_key_event

Send a key down event followed by a key up event:

  $vnc->send_key_event('A');

=head2 send_key_event_string

Send key events for every character in a string:

  $vnc->send_key_event_string('Hello');

=head2 send_pointer_event( $button_mask, $x, $y )

Send pointer event (usually a mouse). This is used to move the pointer or
make clicks or drags.

It is easier to call the C<mouse_move> or <mouse_click> methods instead.

=head2 mouse_move_to($x, $y)

Send the pointer to the given position. The cursor instantly jumps there
instead of smoothly moving to there.

=head2 mouse_click

Click on current pointer position.

=head2 mouse_right_click

Right-click on current pointer position.

=head1 BUGS AND LIMITATIONS

=head2 Bit depth

We do not yet support 8-bit true-colour mode, which is commonly
supported by servers but is rarely employed by clients.

=head2 Byte order

We have currently tested this package against servers with the same
byte order as the client.  This might break with a little-endian
server/big-endian client or vice versa.  We're working on tests for
those latter cases.  Testing and patching help would be appreciated.

=head2 Efficiency

We've implemented a subset of the data compression algorithms
supported by most VNC servers.  We hope to add more of the
high-compression transfer encodings in the future.

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
 

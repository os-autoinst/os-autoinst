# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::SPICE;

use Mojo::Base -base, -signatures;
use IO::Socket::UNIX;
use Mojo::JSON qw(decode_json encode_json);
use bmwqemu qw(diag);

has [qw(hostname port socket _framebuffer width height)];

sub new ($class, $args) {
    my $self = $class->SUPER::new();
    $self->hostname($args->{hostname});
    $self->port($args->{port});
    $self->width(1024);
    $self->height(768);
    return $self;
}

sub login ($self, $timeout = 3) {
    # Resolve socket path based on port (e.g. /tmp/spice-bridge-$port.sock)
    my $socket_path = '/tmp/spice-bridge-' . $self->port . '.sock';

    diag "Connecting to SPICE bridge socket at $socket_path";
    my $socket;
    for (1 .. 30) {
        if (-e $socket_path) {
            $socket = IO::Socket::UNIX->new(
                Type => SOCK_STREAM,
                Peer => $socket_path,
            );
            last if $socket;
        }
        select undef, undef, undef, 0.1;    # sleep 100ms
    }

    # Fallback to default /tmp/spice-bridge.sock if port-specific socket wasn't found/connected
    if (!$socket) {
        $socket_path = '/tmp/spice-bridge.sock';
        diag "Falling back to SPICE bridge socket at $socket_path";
        for (1 .. 10) {
            if (-e $socket_path) {
                $socket = IO::Socket::UNIX->new(
                    Type => SOCK_STREAM,
                    Peer => $socket_path,
                );
                last if $socket;
            }
            select undef, undef, undef, 0.1;
        }
    }

    die "Failed to connect to SPICE bridge socket at $socket_path!\n" unless $socket;
    $self->socket($socket);    ## no critic (ProhibitParensWithBuiltins)
    return $self;
}

sub update_framebuffer ($self) {
    my $socket = $self->socket or die 'No socket available';

    # Send get_frame command
    my $cmd = encode_json({cmd => 'get_frame'}) . "\n";
    $socket->print($cmd);

    # Read response header line (JSON)
    my $resp_line = $socket->getline();
    return unless $resp_line;
    chomp $resp_line;

    my $data = decode_json($resp_line);
    if ($data->{status} eq 'ok') {
        $self->width($data->{width});
        $self->height($data->{height});
        my $size = $data->{size};

        # Read raw binary frame data
        my $raw_data = '';
        my $bytes_read = 0;
        while ($bytes_read < $size) {
            my $chunk;
            my $read_res = $socket->read($chunk, $size - $bytes_read);    ## no critic (ProhibitParensWithBuiltins)
            die 'Unexpected EOF reading frame bytes' if !defined $read_res || $read_res <= 0;
            $raw_data .= $chunk;
            $bytes_read += length $chunk;
        }

        # Convert raw RGB bytes to a tinycv image
        require tinycv;
        my $ppm_header = 'P6' . "\n" . $self->width . ' ' . $self->height . "\n" . '255' . "\n";
        my $image = tinycv::from_ppm($ppm_header . $raw_data);
        $self->_framebuffer($image);
    }
}

sub map_and_send_key ($self, $keys, $down, $delay) {
    my $socket = $self->socket or die 'No socket available';

    my %scancodes = (
        'esc' => 1,
        '1' => 2,
        '2' => 3,
        '3' => 4,
        '4' => 5,
        '5' => 6,
        '6' => 7,
        '7' => 8,
        '8' => 9,
        '9' => 10,
        '0' => 11,
        'minus' => 12,
        '-' => 12,
        'equal' => 13,
        '=' => 13,
        'backspace' => 14,
        'tab' => 15,
        'q' => 16,
        'w' => 17,
        'e' => 18,
        'r' => 19,
        't' => 20,
        'y' => 21,
        'u' => 22,
        'i' => 23,
        'o' => 24,
        'p' => 25,
        '[' => 26,
        ']' => 27,
        'ret' => 28,
        'ctrl' => 29,
        'a' => 30,
        's' => 31,
        'd' => 32,
        'f' => 33,
        'g' => 34,
        'h' => 35,
        'j' => 36,
        'k' => 37,
        'l' => 38,
        'semicolon' => 39,
        ';' => 39,
        'apos' => 40,
        '\'' => 40,
        'grave' => 41,
        '`' => 41,
        'shift' => 42,
        'backslash' => 43,
        '\\' => 43,
        'z' => 44,
        'x' => 45,
        'c' => 46,
        'v' => 47,
        'b' => 48,
        'n' => 49,
        'm' => 50,
        'comma' => 51,
        ',' => 51,
        'dot' => 52,
        '.' => 52,
        'slash' => 53,
        '/' => 53,
        'alt' => 56,
        'spc' => 57,
        ' ' => 57,
        'caps' => 58,
        'f1' => 59,
        'f2' => 60,
        'f3' => 61,
        'f4' => 62,
        'f5' => 63,
        'f6' => 64,
        'f7' => 65,
        'f8' => 66,
        'f9' => 67,
        'f10' => 68,
        'f11' => 87,
        'f12' => 88,
        'home' => 71,
        'up' => 72,
        'pgup' => 73,
        'left' => 75,
        'right' => 77,
        'end' => 79,
        'down' => 80,
        'pgdn' => 81,
        'insert' => 82,
        'delete' => 83,
    );

    my %shift_keys = (
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
        '_' => '-',
        '+' => '=',
        '{' => '[',
        '}' => ']',
        '|' => '\\',
        ':' => ';',
        '"' => '\'',
        '<' => ',',
        '>' => '.',
        '?' => '/',
    );

    my @events;
    for my $key (split /-/, $keys) {
        if ($key =~ /^\d+$/) {
            push @events, int $key;
        }
        elsif (defined $shift_keys{$key}) {
            push @events, 'shift', $shift_keys{$key};
        }
        elsif ($key =~ /^[A-Z]$/) {
            push @events, 'shift', lc $key;
        }
        else {
            push @events, $key;
        }
    }

    my @scancode_events;
    for my $ev (@events) {
        if (defined $scancodes{$ev}) {
            push @scancode_events, $scancodes{$ev};
        }
        elsif ($ev =~ /^\d+$/) {
            push @scancode_events, int $ev;
        }
        else {
            bmwqemu::diag "Unknown key mapping for SPICE: $ev";
        }
    }

    my @states = defined $down ? ($down) : (1, 0);
    $delay //= 0.02;
    my $down_delay = $delay * 0.5;
    $down_delay = 0.01 if $down_delay > 0.01;
    my $up_delay = $delay - $down_delay;

    for my $state (@states) {
        my @list = $state ? @scancode_events : reverse @scancode_events;
        for my $sc (@list) {
            my $final_sc = $state ? $sc : ($sc | 0x80);
            my $cmd = encode_json({
                    cmd => 'key_event',
                    key => "$final_sc",
                    down => $state ? Mojo::JSON->true : Mojo::JSON->false,
            }) . "\n";
            $socket->print($cmd);
            # Read status reply
            my $resp = $socket->getline();
            select undef, undef, undef, ($state ? $down_delay : $up_delay);
        }
    }
}

sub mouse_move_to ($self, $x, $y) {
    my $socket = $self->socket or die 'No socket available';
    my $cmd = encode_json({
            cmd => 'mouse_event',
            x => int($x),
            y => int($y),
            button_mask => 0,
    }) . "\n";
    $socket->print($cmd);

    # Read reply
    my $resp = $socket->getline();
}

sub send_pointer_event ($self, $mask, $x, $y) {
    my $socket = $self->socket or die 'No socket available';
    my $cmd = encode_json({
            cmd => 'mouse_event',
            x => int($x),
            y => int($y),
            button_mask => int($mask),
    }) . "\n";
    $socket->print($cmd);

    # Read reply
    my $resp = $socket->getline();
}

1;

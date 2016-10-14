package consoles::virtio_screen;
use 5.018;
use warnings;
use English qw( -no_match_vars );
use Time::HiRes qw( gettimeofday usleep );

our $VERSION;

sub new {
    my ($class, $socket_fd) = @_;
    my $self = bless {class => $class}, $class;
    $self->{socket_fd} = $socket_fd;
    return $self;
}

my $trying_to_use_keys = <<'FIN.';
Use type_string (possibly with an ANSI/XTERM escape sequence), or switch to a
console which sends key presses, not terminal codes.
FIN.

sub send_key {
    die $trying_to_use_keys;
}

sub hold_key {
    die $trying_to_use_keys;
}

sub release_key {
    die $trying_to_use_keys;
}

=head2 type_string

    type_string($self, $message);

Writes $message to the socket which the guest's terminal is listening on. Unlike
VNC based consoles we just send the bytes making up $message not a series of
keystrokes. This is much faster, but means that special key combinations like
Ctrl-Alt-Del or SysRq may not be possible. However most terminals do support
many escape sequences for scrolling and performing various actions other
than entering text. See ANSI, VT100 and XTERM escape codes.

=cut
sub type_string {
    my ($self, $msg) = @_;
    my $fd = $self->{socket_fd};

    bmwqemu::log_call(message => $msg);

    my $written = syswrite $fd, $msg;
    unless (defined $written) {
        die "Error writing to virtio terminal: $ERRNO";
    }
    if ($written < length($msg)) {
        die "Was not able to write entire message to virtio terminal. Only $written of $msg";
    }
}

=head2 read_until

  read_until($self, $match_expression, $timeout, [
                     buffer_size => 4096, record_output => 0, exclude_match => 0,
                     no_regex => 0
  ]);

Monitor the virtio console socket $file_descriptor for a character sequence which matches
$match_expression. Bytes are read from the socket in up to $buffer_size chunks and each chunk is
added to a ring buffer which is also up to $buffer_size long. The regular expression is tested
against the ring buffer after each read operation.

If $record_output is set then all data from the socket is stored in a separate string and returned.
Otherwise just the contents of the ring buffer will be returned. Setting $exclude_match removes the
matched string from the returned string. Data which was received after a matching set of characters
is lost (although not completely, as it should be in "$socket_path.log").

Setting $no_regex will cause it to do a plain string search using index().

=cut
sub read_until {
    my ($self, $re, $timeout) = @_[0..2];
    my $fd = $self->{socket_fd};
    my %nargs = @_[3..$#_];
    my $buflen = $nargs{buffer_size} || 4096;
    my $overflow = $nargs{record_output} ? '' : undef;
    my $sttime = gettimeofday;
    my ($rbuf, $buf) = ('', '');
    my $loops = 0;
    my ($prematch, $match);

    $nargs{regular_expression} = $re;
    $nargs{timeout} = $timeout;
    bmwqemu::log_call(%nargs);

  READ: while(1) {
        $loops++;
        if (gettimeofday() - $sttime >= $timeout) {
            # TODO: Return fail to the caller instead of dieing so that the test
            #       can collect logs or perform a workaround
            die 'Timeout exceeded on virtio console assert, read: ' . $rbuf;
        }

        my $read = sysread($fd, $buf, $buflen);
        unless (defined $read) {
            if ($ERRNO{EAGAIN} || $ERRNO{EWOULDBLOCK}) {
                usleep(100);
                next READ;
            }
            die "Failed to read from virtio console char device: $ERRNO";
        }

        # If there is not enough free space in the ring buffer; remove an amount
        # equal to the bytes just read minus the free space in $rbuf from the
        # begining. If we are recording all output, add the removed bytes to
        # $overflow.
        if (length($rbuf) + $read > $buflen) {
            my $remove_len = $read - ($buflen - length($rbuf));
            if (defined $overflow) {
                $overflow .= substr $rbuf, 0, $remove_len;
            }
            $rbuf = substr $rbuf, $remove_len;
        }
        $rbuf .= $buf;

        # Search ring buffer for a match and exit if we find it
        if ($nargs{no_regex}) {
            my $i = index($rbuf, $re);
            if ($i >= 0) {
                $match = substr $rbuf, $i, length($re);
                $prematch = substr $rbuf, 0, $i;
                last READ;
            }
        }
        elsif ($rbuf =~ m/$re/) {
            # See match variable perf issues: http://bit.ly/2dbGrzo
            $prematch = substr $rbuf, 0, $LAST_MATCH_START[0];
            $match = substr $rbuf, $LAST_MATCH_START[0], $LAST_MATCH_END[0] - $LAST_MATCH_START[0];
            last READ;
        }
    }

    my $elapsed = gettimeofday() - $sttime;
    bmwqemu::fctinfo("Matched output from SUT in $loops loops & $elapsed seconds: $match");

    $overflow ||= '';
    if ($nargs{exclude_match}) {
        return $overflow . $prematch;
    }
    return $overflow . $prematch . $match;
}

sub current_screen {
    # TODO: We could generate a bitmap of the terminal text, but I think it would be misleading.
    #       Instead we should use a text terminal viewer in the browser if possible.
    return 0;
}

1;

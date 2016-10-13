package consoles::virtio_screen;
use 5.018;
use warnings;
use English qw( -no_match_vars );
use Time::HiRes qw( gettimeofday usleep );
# Do not use autodie in this module, it breaks non-blocking sockets

our $VERSION;

sub new {
    my ($class, $socket_fd) = @_;
    my $self = bless {class => $class}, $class;
    $self->{socket_fd} = $socket_fd;
    return $self;
}

sub send_key {
    type_string(@_);
}

sub hold_key {
    ...
}

sub release_key {
    ...
}

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
is lost (although not completely, as it will be in "$socket_path.log").

Setting $no_regex will cause it to do a plain string search instead using index().

=cut
sub read_until {
    my ($self, $re, $timeout) = @_[0..2];
    my $fd = $self->{socket_fd};
    my %nargs = @_[3..$#_];
    my $buflen = $nargs{buffer_size} || 4096;
    my $rbuf = '';
    my $buf = '';
    my $data = $nargs{record_output} ? '' : undef;
    my $sttime = gettimeofday;
    my $loops = 0;
    my ($prematch, $match);

    $nargs{regular_expression} = $re;
    $nargs{timeout} = $timeout;
    bmwqemu::log_call(%nargs);

  READ: while(1) {
        $loops++;
        if (gettimeofday() - $sttime >= $timeout) {
            # TODO: Replace a lot of these die calls with vconsole_record_result(<title>, 'fail',...)
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

        if (length($rbuf) + $read > $buflen) {
            # If there is not enough free space in the ring buffer remove the
            # amount just read minus any free space. TODO: Test it with low buffer size
            $rbuf = substr $rbuf, $read - ($buflen - length($rbuf));
        }
        $rbuf .= $buf;

        if ($nargs{no_regex}) {
            my $i = index($rbuf, $re);
            if ($i >= 0) {
                $match = substr $rbuf, $i, length($re);
                $prematch = substr $rbuf, 0, $i;
                last READ;
            }
        }
        elsif ($rbuf =~ m/$re/) {
            # See perf issues: http://bit.ly/2dbGrzo
            $prematch = substr $rbuf, 0, $LAST_MATCH_START[0];
            $match = substr $rbuf, $LAST_MATCH_START[0], $LAST_MATCH_END[0] - $LAST_MATCH_START[0];
            last READ;
        }

        if (defined $data) {
            $data .= $buf;
        }
    }

    my $trailing;
    unless ($nargs{exclude_match}) {
        $trailing = $prematch . $match;
    }else{
        $trailing = $prematch;
    }

    if (defined $data) {
        $data .= substr $trailing, length($rbuf) - length($buf);
    }
    else {
        $data = $trailing;
    }

    my $elapsed = gettimeofday() - $sttime;
    bmwqemu::fctinfo("Matched output from SUT in $loops loops & $elapsed seconds: $match");

    return $data;
}

sub current_screen {
    # TODO: We could generate a bitmap of the terminal text, but I think it would be misleading.
    #       Instead we should use a text terminal viewer in the browser if possible.
    return 0;
}

1;

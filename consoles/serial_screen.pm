# Copyright © 2016-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.
package consoles::serial_screen;

use 5.018;
use Mojo::Base -strict, -signatures;
use integer;

use English -no_match_vars;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use Carp 'croak';

our $VERSION;

sub new ($class, $fd_read, $fd_write) {
    my $self;
    if (ref($class) ne '' && $class->isa('consoles::serial_screen')) {
        $self = $class;
    } else {
        $self = bless {class => $class}, $class;
    }

    $self->{fd_read}      = $fd_read;
    $self->{fd_write}     = $fd_write // $fd_read;
    $self->{carry_buffer} = '';

    return $self;
}

my $trying_to_use_keys = <<'FIN.';
Virtio terminal and svirt serial terminal do not support send_key. Use
type_string (possibly with an ANSI/XTERM escape sequence), or switch to a
console which sends key presses, not terminal codes.
FIN.

=head2 send_key

    send_key(key => 'ret');

This is mostly redundant for the time being, use C<type_string> instead. Many
testapi functions use C<send_key('ret')> however so that particular case has
been implemented. In the future this could be extended to provide more key
name to terminal code mappings.

=cut
sub send_key ($self, $nargs) {
    if ($nargs->{key} eq 'ret') {
        $nargs->{text} = "\n";
        $self->type_string($nargs);
    }
    else {
        croak $trying_to_use_keys;
    }
}

sub hold_key { croak $trying_to_use_keys }

sub release_key { croak $trying_to_use_keys }

=head2 type_string

    type_string($self, $message, terminate_with => '');

Writes C<$message> to the socket which the guest's terminal is listening on.
Unlike VNC based consoles we just send the bytes making up C<$message>, not a
series of keystrokes. This is much faster, but means that special key
combinations like Ctrl-Alt-Del or SysRq[1] may not be possible. However most
terminals do support many escape sequences for scrolling and performing
various actions other than entering text. See C0, C1, ANSI, VT100 and XTERM
escape codes.

The optional terminate_with argument can be set to EOT (End Of Transmission),
ETX (End Of Text). Sending EOT should have the same effect as pressing Ctrl-D
and ETX is the same as pressing Ctrl-C on a terminal.

[1] It appears sending 0x0f will press the SysRq key down on hvc based
consoles.

=cut
sub type_string ($self, $nargs) {
    my $fd = $self->{fd_write};

    bmwqemu::log_call(%$nargs);

    my $text = $nargs->{text};
    my $term;
    for ($nargs->{terminate_with} || '') {
        if    (/^ETX$/) { $term = "\cC"; }    #^C, Ctrl-c, End Of Text
        elsif (/^EOT$/) { $term = "\cD"; }    #^D, Ctrl-d, End Of Transmission
    }

    $text .= $term if defined $term;
    my $written = syswrite $fd, $text;
    unless (defined $written) {
        croak "Error writing to virtio/svirt serial terminal: $ERRNO";
    }
    if ($written < length($text)) {
        croak "Was not able to write entire message to virtio/svirt serial terminal. Only $written of $nargs->{text}";
    }
}

sub thetime { clock_gettime(CLOCK_MONOTONIC) }

sub elapsed ($start) {
    no integer;
    return thetime() - $start;
}

sub remaining ($start, $timeout) {
    no integer;
    return $timeout - elapsed($start);
}

# If $pattern is an array of regexes combine them into a single one.
# If $pattern is a single string, wrap it in an array.
# Otherwise leave as is.
sub normalise_pattern ($pattern, $no_regex) {

    if (ref $pattern eq 'ARRAY' && !$no_regex) {
        my $hr = shift @$pattern;
        if (@$pattern > 0) {
            my $re = qr/($hr)/;
            for my $r (@$pattern) {
                $re .= qr/|($r)/;
            }
            return $re;
        }
        return $hr;
    }

    if ($no_regex && ref $pattern ne 'ARRAY') {
        return [$pattern];
    }

    return $pattern;
}

=head2 do_read

  my $num_read = do_read($buffer [, max_size => 2048][,timeout => undef]);

Attempts to read up to max_size bytes from C<<$self->{fd_read}>> into a
buffer. The method returns as soon as some data is available, even if the
given size has not been reached. Returns the number of bytes read or undef on
timeout. Note that 0 is a valid return code. If a failure occurs the method
will croak.

An undefined timeout will cause to wait indefinitely. A timeout of 0 means to
just read once.

=cut
sub do_read ($self, undef, %args) {
    my $buffer = '';
    $args{timeout}  //= undef;    # wait till data is available
    $args{max_size} //= 2048;
    my $fd = $self->{fd_read};

    my $rin = '';
    vec($rin, fileno($fd), 1) = 1;
    my $nfound = select(my $rout = $rin, undef, my $eout = $rin, $args{timeout});
    if ($nfound < 0) {
        croak "Failed to select socket for reading: $ERRNO";
    } elsif ($nfound == 0) {
        return undef;
    }

    my $read;
    while (!defined($read)) {
        $read = sysread($fd, $buffer, $args{max_size});
        if (!defined($read) && !($ERRNO{EAGAIN} || $ERRNO{EWOULDBLOCK})) {
            croak "Failed to read from virtio/svirt serial console char device: $ERRNO";
        }
    }
    $_[1] = $buffer;
    return $read;
}

=head2 read_until

  read_until($self, $pattern, $timeout, [
                     buffer_size => 4096, record_output => 0, exclude_match => 0,
                     no_regex => 0
  ]);

Monitor the virtio/svirt serial console socket C<$file_descriptor> for a
character sequence which matches C<$pattern>. Bytes are read from the socket
in up to C<$buffer_size/2> chunks and each chunk is added to a ring buffer
which is C<$buffer_size> long. The regular expression is tested against the
ring buffer after each read operation. Note, the reason we are using a ring
buffer is to avoid matches failing because the matching text is split between
two reads.

If C<$record_output> is set then all data from the socket is stored in a
separate string and returned. Otherwise just the contents of the ring buffer
will be returned.

Setting C<$exclude_match> removes the matched string from the returned string.

Data which was read after a matching set of characters is saved to a carry
buffer and used in the next call to read_until (unless the console is reset).
If the match fails the whole ring buffer is carried over to the next call.

Setting C<$no_regex> will cause it to do a plain string search using
C<index()>.

Returns a map reference like
C<{ matched => 1, string => 'text from the terminal' }>
on success and
C<{ matched => 0, string => 'text from the terminal' }>
on failure.

=cut
sub read_until ($self, $pattern, $timeout) {
    my $fd       = $self->{fd_read};
    my %nargs    = @_[3 .. $#_];
    my $buflen   = $nargs{buffer_size} || 4096;
    my $overflow = $nargs{record_output} ? '' : undef;
    my $sttime   = thetime();
    my ($rbuf, $buf) = ($self->{carry_buffer}, '');
    my $loops = 0;
    my ($prematch, $match);

    my $re = normalise_pattern($pattern, $nargs{no_regex});

    $nargs{pattern} = $re;
    $nargs{timeout} = $timeout;
    bmwqemu::log_call(%nargs);

  READ: while (1) {
        $loops++;

        # Search ring buffer for a match and exit if we find it
        if ($nargs{no_regex}) {
            for my $p (@$re) {
                my $i = index($rbuf, $p);
                if ($i >= 0) {
                    $match                = substr $rbuf, $i, length($p);
                    $prematch             = substr $rbuf, 0, $i;
                    $self->{carry_buffer} = substr $rbuf, $i + length($p);
                    last READ;
                }
            }
        }
        elsif ($rbuf =~ m/$re/) {
            # See match variable perf issues: http://bit.ly/2dbGrzo
            $prematch             = substr $rbuf, 0, $LAST_MATCH_START[0];
            $match                = substr $rbuf, $LAST_MATCH_START[0], $LAST_MATCH_END[0] - $LAST_MATCH_START[0];
            $self->{carry_buffer} = substr $rbuf, $LAST_MATCH_END[0];
            last READ;
        }

        if (elapsed($sttime) >= $timeout) {
            $self->{carry_buffer} = $rbuf;
            return {matched => 0, string => ($overflow || '') . $rbuf};
        }

        my $read = $self->do_read($buf, max_size => $buflen / 2, timeout => remaining($sttime, $timeout));
        next READ unless (defined($read));

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
    }

    my $elapsed = elapsed($sttime);
    bmwqemu::fctinfo("Matched output from SUT in $loops loops & $elapsed seconds: $match");

    $overflow ||= '';
    if ($nargs{exclude_match}) {
        return $overflow . $prematch;
    }
    return {matched => 1, string => $overflow . $prematch . $match};
}

=head2 peak

Read and return pending data without consuming it. This is useful if you are
about to destroy the serial_screen instance, but want to keep any pending
data. However this does not wait for any data in particular so this races with
the backend and data transport. Therefor it should only be used when there is
no information available about what data is expected to be available.

=cut
sub peak ($self, %nargs) {
    my $buflen     = $nargs{buffer_size} || 4096;
    my $total_read = 0;
    my $buf        = '';
    my $read;

    bmwqemu::log_call(%nargs);
  LOOP: {
        $read = sysread($self->{fd_read}, $buf, $buflen);
        last LOOP unless defined $read;

        $self->{carry_buffer} .= $buf;
        $total_read += $read;

        next LOOP if $read > 0 && $total_read < $buflen;
    }

    bmwqemu::fctinfo('Peaked ' . ($total_read + length($self->{carry_buffer})) . ' bytes');
    return $self->{carry_buffer};
}

sub current_screen { 0 }

sub request_screen_update { }

1;

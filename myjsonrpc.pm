# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package myjsonrpc;

use Mojo::Base -strict, -signatures;
use Carp qw(cluck confess);
use IO::Select;
use Errno;
use Mojo::JSON;    # booleans
use Cpanel::JSON::XS ();
use bmwqemu ();

use constant DEBUG_JSON => $ENV{PERL_MYJSONRPC_DEBUG} || 0;
use constant READ_BUFFER => $ENV{PERL_MYJSONRPC_BYTES} || 8_000_000;

my $interleaved_command_handler;    # handler to deal with commands received while waiting for another reply

sub set_interleaved_command_handler ($handler_or_array) {
    $interleaved_command_handler = ref $handler_or_array eq 'ARRAY' ? sub (@args) { push @$handler_or_array, \@args } : $handler_or_array;
}

sub _syswrite ($to_fd, $json, $length = undef, $offset = undef) { syswrite $to_fd, $json, $length, $offset }

sub is_debug () { DEBUG_JSON || $bmwqemu::vars{DEBUG_JSON_RPC} }

sub handle_read_error ($fd) {
    # throw an error except can_read has been interrupted
    my $error = $!;
    confess "ERROR: unable to wait for JSON reply: $error\n" unless $!{EINTR};
    # try again if can_read's underlying system call has been interrupted as suggested by the perlipc documentation
    bmwqemu::diag("read_json($fd): can_read's underlying system call has been interrupted, trying again\n") if is_debug;    # uncoverable statement
}

sub send_json ($to_fd, $cmd) {
    # allow regular expressions to be automatically converted into
    # strings, using the Regex::TO_JSON function as defined at the end
    # of this file.
    # The resulting JSON should be in a single line, otherwise
    # read_json won't work
    my $cjx = Cpanel::JSON::XS->new->canonical->utf8->convert_blessed();

    # deep copy to add a random string
    my %cmdcopy = %$cmd;
    # The hash might already contain a json_cmd_token
    $cmdcopy{json_cmd_token} ||= bmwqemu::random_string(8);

    my $json = $cjx->encode(\%cmdcopy);
    bmwqemu::diag(sprintf 'send_json(%d) JSON=%s', fileno($to_fd), $json =~ s/"([^"]{30})[^"]+"/"$1"/gr) if is_debug();
    $json .= "\n";

    confess 'myjsonrpc: called on undefined file descriptor' unless defined $to_fd;
    my $written_bytes = 0;
    my $bytes_to_write = length $json;
    while ($written_bytes < $bytes_to_write) {
        $written_bytes += _syswrite($to_fd, $json, $bytes_to_write - $written_bytes, $written_bytes) // 0;
        if ($!) {
            die 'myjsonrpc: remote end terminated connection, stopping' if !DEBUG_JSON && $! =~ qr/Broken pipe/;
            confess sprintf "syswrite failed: err: '%s'; written_bytes: %d/%d; JSON: '%s'", $!, $written_bytes, $bytes_to_write, $json;
        }
    }
    return $cmdcopy{json_cmd_token};
}

# utility function
my %RESULTS;
my %CJX;

sub _extract_result_for_cmd_token ($results, $cmd_token, $multi) {
    return undef if $multi;
    my $i = 0;
    for my $hash (@$results) {
        if ($cmd_token && ($hash->{json_cmd_token} || '') ne $cmd_token) {
            ++$i;
            next;
        }
        return splice @$results, $i, 1;
    }
    return undef;
}

sub read_json ($socket, $cmd_token = undef, $multi = undef) {
    my $fd = fileno $socket;
    bmwqemu::diag("read_json($fd)") if is_debug();

    # return excess result from previous invocation
    my $results = $RESULTS{$fd} //= [];
    my $single_result = _extract_result_for_cmd_token($results, $cmd_token, $multi);
    return $single_result if defined $single_result;
    return splice @$results if $multi && @$results;

    my $cjx = $CJX{$fd} //= Cpanel::JSON::XS->new->utf8;
    my $s = IO::Select->new();
    $s->add($socket);

    # the goal here is to find the end of the next valid JSON - and don't
    # add more data to it. As the backend sends things unasked, we might
    # run into the next message otherwise
    while (1) {
        my $hash = $cjx->incr_parse();
        if ($hash) {
            bmwqemu::diag(sprintf 'read_json(%d) json_cmd_token=%s', $fd, $hash->{json_cmd_token} // 'no-token') if is_debug();
            if ($hash->{QUIT}) {
                bmwqemu::diag('received magic close');
                push @$results, undef;
                last;
            }
            if ($cmd_token && ($hash->{json_cmd_token} || '') ne $cmd_token) {
                $interleaved_command_handler ? $interleaved_command_handler->($hash, $socket) : (push @$results, $hash);
                next;
            }
            else {
                push @$results, $hash;
                # parse all lines from buffer
                next if $multi;
                last;
            }
        }
        elsif ($multi and @$results) {
            # read at least one item in list context
            last;
        }

        # wait for next read
        handle_read_error($fd) until (my @res = $s->can_read);

        my $qbuffer;
        if (!sysread $socket, $qbuffer, READ_BUFFER) { bmwqemu::fctwarn("sysread failed: $!") if is_debug(); return $multi ? () : undef }
        $cjx->incr_parse($qbuffer);
    }

    return splice @$results if $multi;
    return _extract_result_for_cmd_token($results, $cmd_token, $multi);
}

###################################################################
# enable send_json to send regular expressions
#<<< perltidy off
# this has to be on two lines so other tools don't believe this file
# exports package Regexp
package
Regexp;
#>>> perltidy on
sub TO_JSON ($regex) {
    $regex = "$regex";
    return $regex;
}

1;

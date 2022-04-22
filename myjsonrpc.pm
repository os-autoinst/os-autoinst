# Copyright 2012-2021 SUSE LLC
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
use constant READ_BUFFER => $ENV{PERL_MYJSONRPC_BYTES} || 8000000;

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
    if (DEBUG_JSON) {
        my $copy = $json;
        # shorten long content
        $copy =~ s/"([^"]{30})[^"]+"/"$1"/g;
        my $fd = fileno($to_fd);
        bmwqemu::diag("($$) send_json($fd) JSON=$copy");
    }
    $json .= "\n";

    confess 'myjsonprc: called on undefined file descriptor' unless defined $to_fd;
    my $wb = syswrite($to_fd, "$json");
    if (!$wb || $wb != length($json)) {
        die('myjsonrpc: remote end terminated connection, stopping') if !DEBUG_JSON && $! =~ qr/Broken pipe/;
        confess "syswrite failed: $!";
    }
    return $cmdcopy{json_cmd_token};
}

# hash for keeping state
our $sockets;

# utility function
sub read_json ($socket, $cmd_token = undef, $multi = undef) {
    my $cjx = Cpanel::JSON::XS->new;

    my $fd = fileno($socket);
    bmwqemu::diag("($$) read_json($fd)") if DEBUG_JSON;
    if (exists $sockets->{$fd}) {
        # start with the trailing text from previous call
        my $buffer = delete $sockets->{$fd};
        $cjx->incr_parse($buffer);
    }

    my $s = IO::Select->new();
    $s->add($socket);

    my @results;

    # the goal here is to find the end of the next valid JSON - and don't
    # add more data to it. As the backend sends things unasked, we might
    # run into the next message otherwise
    while (1) {
        my $hash = $cjx->incr_parse();
        # remember the trailing text
        if ($hash) {
            $sockets->{$fd} = $cjx->incr_text();
            if (DEBUG_JSON) {
                my $token = $hash->{json_cmd_token} // 'no-token';
                bmwqemu::diag("($$) read_json($fd) json_cmd_token=$token");
            }
            if ($hash->{QUIT}) {
                bmwqemu::diag("received magic close");
                push @results, undef;
                last;
            }
            confess "ERROR: the token does not match - questions and answers not in the right order" if $cmd_token && ($hash->{json_cmd_token} || '') ne $cmd_token; # uncoverable statement
            push @results, $hash;
            # parse all lines from buffer
            next if $multi;
            last;
        }
        elsif ($multi and @results) {
            # read at least one item in list context
            last;
        }

        # wait for next read
        my @res = $s->can_read;
        while (!@res) {
            # throw an error except can_read has been interrupted
            my $error = $!;
            confess "ERROR: unable to wait for JSON reply: $error\n" unless $!{EINTR};
         # try again if can_read's underlying system call has been interrupted as suggested by the perlipc documentation
            bmwqemu::diag("($$) read_json($fd): can_read's underlying system call has been interrupted, trying again\n") if DEBUG_JSON;
            @res = $s->can_read;
        }

        my $qbuffer;
        my $bytes = sysread($socket, $qbuffer, READ_BUFFER);
        if (!$bytes) {
            bmwqemu::fctwarn("sysread failed: $!") if DEBUG_JSON;
            return;
        }
        $cjx->incr_parse($qbuffer);
    }

    return $multi ? @results : $results[0];
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

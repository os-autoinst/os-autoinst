# Copyright © 2012-2016 SUSE LLC
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

package myjsonrpc;

use strict;
use warnings;
use Carp qw(cluck confess);
use bmwqemu ();
use Errno;
use Mojo::JSON;    # booleans
use Cpanel::JSON::XS ();

sub send_json {
    my ($to_fd, $cmd) = @_;

    # allow regular expressions to be automatically converted into
    # strings, using the Regex::TO_JSON function as defined at the end
    # of this file.
    my $cjx = Cpanel::JSON::XS->new->convert_blessed();
    # deep copy to add a random string
    my %cmdcopy = %$cmd;
    $cmdcopy{json_cmd_token} = bmwqemu::random_string(8);
    my $json = $cjx->encode(\%cmdcopy);

    #bmwqemu::diag("send_json $json");
    my $wb = syswrite($to_fd, "$json");
    confess "syswrite failed $!" unless ($wb && $wb == length($json));
    return $cmdcopy{json_cmd_token};
}

# hash for keeping state
our $sockets;

# utility function
sub read_json {
    my ($socket, $cmd_token) = @_;

    my $cjx = Cpanel::JSON::XS->new;

    my $fd = fileno($socket);
    if (exists $sockets->{$fd}) {
        # start with the trailing text from previous call
        $cjx->incr_parse($sockets->{$fd});
        delete $sockets->{$fd};
    }

    my $s = IO::Select->new();
    $s->add($socket);

    my $hash;

    # the goal here is to find the end of the next valid JSON - and don't
    # add more data to it. As the backend sends things unasked, we might
    # run into the next message otherwise
    while (1) {
        $hash = $cjx->incr_parse();
        if ($hash) {
            # remember the trailing text
            $sockets->{$fd} = $cjx->incr_text();
            if ($hash->{QUIT}) {
                bmwqemu::diag("received magic close");
                return;
            }
            if ($cmd_token && ($hash->{json_cmd_token} || '') ne $cmd_token) {
                confess "ERROR: the token does not match - questions and answers not in the right order";
            }
            return $hash;
        }

        # wait for next read
        my @res = $s->can_read;
        unless (@res) {
            my $E = $!;    # save the error
            unless ($!{EINTR}) {    # EINTR if killed
                confess "ERROR: timeout reading JSON reply: $E\n";
            }
            else {
                die("can_read received kill signal");
            }
            close($socket);
            return;
        }

        my $qbuffer;
        my $bytes = sysread($socket, $qbuffer, 8000);
        #bmwqemu::diag("sysread $qbuffer");
        if (!$bytes) { bmwqemu::diag("sysread failed: $!"); return; }
        $cjx->incr_parse($qbuffer);
    }

    return $hash;
}

###################################################################
# enable send_json to send regular expressions
#<<< perltidy off
# this has to be on two lines so other tools don't believe this file
# exports package Regexp
package
Regexp;
#>>> perltidy on
sub TO_JSON {
    my $regex = shift;
    $regex = "$regex";
    return $regex;
}

1;

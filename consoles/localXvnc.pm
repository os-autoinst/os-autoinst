# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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

package consoles::localXvnc;
use base 'consoles::vnc_base';
use strict;
use warnings;
use IPC::Run ();

require IPC::System::Simple;
use autodie ':all';
use Socket;
use strict;
use warnings;

sub activate {
    my ($self) = @_;

    # start Xvnc on a random high port and use that port also as $DISPLAY

    my $tcpproto = getprotobyname('tcp');
    my $s;
    socket($s, PF_INET, SOCK_STREAM, $tcpproto) || bmwqemu::logdie "socket: $!\n";
    bind($s, sockaddr_in(0, INADDR_ANY));
    my ($port) = sockaddr_in(getsockname($s));

    my $display = ":$port";
    my $pid     = fork();
    bmwqemu::logdie unless defined $pid;
    if (!$pid) {
        listen($s, 1);
        my $peer;
        accept($peer, $s);
        close($s);
        open(STDIN,  "<&", $peer);
        open(STDOUT, ">&", $peer);
        close($peer);
        exec("Xvnc -depth 16 -inetd -SecurityTypes None -ac $display");
    }
    close($s);
    #print "$self->{testapi_console} -> $port\n";

    $self->connect_vnc(
        {
            hostname => "localhost",
            port     => $port,
            ikvm     => 0
        });
    $self->{DISPLAY} = $display;
    sleep 1;

    # we need a window manager for fullscreen apps to work
    system("DISPLAY=$display icewm -c $bmwqemu::scriptdir/consoles/icewm.cfg &");

    return;
}

sub disable {
    my ($self) = @_;

    return unless $self->{local_X_handle};

    # FIXME shut down more gracefully, some processes may still be
    # open on Xvnc.
    IPC::Run::signal($self->{local_X_handle}, 'TERM');
    IPC::Run::signal($self->{local_X_handle}, 'KILL');
    IPC::Run::finish($self->{local_X_handle});
    $self->{local_X_handle} = undef;
    return;
}

sub DESTROY {
    my $self = shift;
    $self->disable();
    return;
}

1;

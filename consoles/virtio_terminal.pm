# Copyright © 2016 SUSE LLC
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
package consoles::virtio_terminal;
use 5.018;
use warnings;
use autodie;
use Socket qw(SOCK_NONBLOCK PF_UNIX SOCK_STREAM sockaddr_un);
use Errno qw(EAGAIN EWOULDBLOCK);
use English -no_match_vars;
use Carp 'croak';
use Scalar::Util 'blessed';
use Cwd;
use consoles::virtio_screen ();
use testapi 'get_var';

use base 'consoles::console';

our $VERSION;

=head1 NAME

consoles::virtio_terminal

=head1 SYNOPSIS

Provides functions to allow the testapi to interact with a text only console.

=head1 DESCRIPTION

This console can be requested when the backend (usually QEMU/KVM) and guest OS
support virtio serial and virtio console. The guest also needs to be in a state
where it can start a tty on the virtual console. By default openSUSE and SLE
automatically start agetty when the kernel finds the virtio console device, but
another OS may require some additional configuration.

It may also be possible to use a transport other than virtio. This code just
requires a UNIX socket which inputs and outputs terminal ASCII/ANSI codes.

=head1 SUBROUTINES/METHODS

=cut

sub new {
    my ($class, $testapi_console, $args) = @_;
    my $self = $class->SUPER::new($testapi_console, $args);
    $self->{socket_fd}      = 0;
    $self->{socket_path}    = cwd() . '/virtio_console';
    $self->{snapshots}      = {};
    $self->{preload_buffer} = '';
    return $self;
}

sub screen {
    my ($self) = @_;
    return $self->{screen};
}

sub disable {
    my ($self) = @_;
    if ($self->{socket_fd} > 0) {
        close $self->{socket_fd};
        $self->{socket_fd} = 0;
        $self->{screen}    = undef;
    }
}

sub save_snapshot {
    my ($self, $name) = @_;

    if (defined($self->{screen})) {
        $self->{snapshots}->{$name} = $self->{screen}->peak();
    } else {
        $self->{snapshots}->{$name} = '';
    }
}

sub load_snapshot {
    my ($self, $name) = @_;

    if (defined($self->{screen})) {
        $self->{screen}->{carry_buffer} = $self->{snapshots}->{$name};
    } else {
        $self->{preload_buffer} = $self->{snapshots}->{$name};
    }
}

=head2 socket_path

The file system path bound to a UNIX socket which will be used to transfer
terminal data between the host and guest.

=cut
sub socket_path {
    my ($self) = @_;
    return $self->{socket_path};
}

=head2 open_socket

  open_socket();

Opens a unix socket to the character device located at $socket_path.

Returns the file descriptor for the open socket, otherwise it dies.

=cut
sub open_socket {
    my ($self) = @_;
    my $fd;
    bmwqemu::log_call(socket_path => $self->socket_path);

    (-S $self->socket_path) || croak 'Could not find ' . $self->socket_path;
    socket($fd, PF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0)
      || croak 'Could not create Unix socket: ' . $ERRNO;
    connect($fd, sockaddr_un($self->socket_path))
      || croak 'Could not connect to virtio-console chardev socket: ' . $ERRNO;

    return $fd;
}

sub activate {
    my ($self) = @_;
    if (get_var('VIRTIO_CONSOLE')) {
        $self->{socket_fd}              = $self->open_socket;
        $self->{screen}                 = consoles::virtio_screen::->new($self->{socket_fd});
        $self->{screen}->{carry_buffer} = $self->{preload_buffer};
        $self->{preload_buffer}         = '';
    }
    else {
        croak 'VIRTIO_CONSOLE is not set, so no virtio-serial and virtconsole devices will be available to use with this console.';
    }
    return;
}

sub is_serial_terminal {
    return 1;
}

1;

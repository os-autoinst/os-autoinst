package consoles::virtio_terminal;
use 5.018;
use warnings;
use autodie;
use Socket qw(SOCK_NONBLOCK PF_UNIX SOCK_STREAM sockaddr_un);
use Errno qw(EAGAIN EWOULDBLOCK);
use Carp qw(cluck);
use Scalar::Util qw(blessed);
use Cwd;
use consoles::virtio_screen ();

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
    $self->{socket_fd} = 0;
    $self->{socket_path} = cwd() . '/virtio_console';
    return $self;
}

sub screen {
    my $self = shift;
    return $self->{screen};
}

sub reset {
    my $self = shift;
    if ($self->{socket_fd} > 0) {
        close($self->{socket_fd});
        $self->{socket_fd} = 0;
        $self->{screen} = undef;
    }
    return $self->SUPER::reset;
}

sub trigger_select {
    my $self = shift;
    die 'Not imlpementd';
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
    my $fd;
    bmwqemu::log_call(socket_path => $socket_path);
    unless (-S $socket_path) {
        die "Could not find $socket_path";
    }
    unless (socket($fd, PF_UNIX, SOCK_STREAM|SOCK_NONBLOCK, 0)) {
        die "Could not create Unix socket: $!";
    }
    unless (connect($fd, sockaddr_un($socket_path))) {
        die "Could not connect to virtio-console chardev socket: $!";
    }
    return $fd;
}

sub activate {
    my $self = shift;
    $self->{socket_fd} = open_socket;
    $self->{screen} = consoles::virtio_screen::->new($self->{socket_fd});
}

1;

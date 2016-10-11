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

sub new {
    my ($class, $testapi_console, $args) = @_;
    my $self = $class->SUPER::new($testapi_console, $args);
    $self->{socket_fd} = 0;
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
    die('Not imlpementd');
}

=head2 $socket_path

Below is the path to a character device file created by QEMU on the host.
This file is backed by a console/tty running on the guest assuming it
runs agetty and the virtio console driver is in the guest's kernel. Any
data written to the file should be interpretted as user input by the tty
running in the guest.

=cut
my $socket_path = cwd() . '/virtio_console';

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

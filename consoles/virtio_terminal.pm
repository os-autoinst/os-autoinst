# Copyright 2016-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
package consoles::virtio_terminal;

use Mojo::Base 'consoles::console', -signatures;
use autodie;
use Mojo::File 'path';
use Socket qw(SOCK_NONBLOCK PF_UNIX SOCK_STREAM sockaddr_un);
use Errno qw(EAGAIN EWOULDBLOCK);
use English -no_match_vars;
use Carp 'croak';
use Scalar::Util 'blessed';
use Cwd;
use consoles::serial_screen ();
use Fcntl;

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

It may also be possible to use a transport other than virtio. This code
uses two pipes to communicate with virtio_consoles from qemu.

=head1 SUBROUTINES/METHODS

=head1 TESTING

For testing you can use:

https://github.com/os-autoinst/os-autoinst-distri-opensuse/blob/master/tests/kernel/virtio_console.pm
https://github.com/os-autoinst/os-autoinst-distri-opensuse/blob/master/tests/kernel/virtio_console_long_output.pm
https://github.com/os-autoinst/os-autoinst-distri-opensuse/blob/master/tests/kernel/virtio_console_user.pm

=cut

sub new ($class, $testapi_console, $args) {
    my $self = $class->SUPER::new($testapi_console, $args);
    $self->{fd_read} = 0;
    $self->{fd_write} = 0;
    $self->{pipe_prefix} = $self->{args}->{socked_path} // cwd() . '/virtio_console';
    $self->{snapshots} = {};
    $self->{preload_buffer} = '';
    return $self;
}

sub screen ($self) { $self->{screen} }

sub disable ($self) {
    return undef unless $self->{fd_read} > 0;
    close $self->{fd_read};
    close $self->{fd_write};
    $self->{fd_read} = 0;
    $self->{fd_write} = 0;
    $self->{screen} = undef;
}

sub save_snapshot ($self, $name) {
    $self->set_snapshot($name, 'activated', $self->{activated});
    $self->set_snapshot($name, 'buffer', $self->{screen} ? $self->{screen}->peak() : $self->{preload_buffer});
}

sub load_snapshot ($self, $name) {
    $self->{activated} = $self->get_snapshot($name, 'activated') // 0;
    my $buffer = $self->get_snapshot($name, 'buffer') // '';
    if (defined($self->{screen})) {
        $self->{screen}->{carry_buffer} = $buffer;
    } else {
        $self->{preload_buffer} = $buffer;
    }
}

sub get_snapshot ($self, $name, $key = undef) {
    my $snapshot = $self->{snapshots}->{$name};
    return (defined($key) && $snapshot) ? $snapshot->{$key} : $snapshot;
}

sub set_snapshot ($self, $name, $key, $value = undef) {
    $self->{snapshots}->{$name}->{$key} = $value;
}

=head2 F_GETPIPE_SZ
This is a helper method for system which do not have F_GETPIPE_SZ in
there Fcntl bindings. See https://perldoc.perl.org/Fcntl.html
=cut
sub F_GETPIPE_SZ () { eval 'no warnings "all"; Fcntl::F_GETPIPE_SZ;' || 1032 }

=head2 F_SETPIPE_SZ
This is a helper method for system which do not have F_SETPIPE_SZ in
there Fcntl bindings. See: https://perldoc.perl.org/Fcntl.html
=cut
sub F_SETPIPE_SZ () { eval 'no warnings "all"; Fcntl::F_SETPIPE_SZ;' || 1031 }

sub set_pipe_sz ($self, $fd, $newsize) {
    no autodie;
    return fcntl($fd, F_SETPIPE_SZ(), int($newsize));
}

sub get_pipe_sz ($self, $fd) { fcntl($fd, F_GETPIPE_SZ(), 0) }

=head2 open_pipe

  open_pipe();

Opens a the read and write pipe based on C<$pipe_prefix>.

Returns the read and write file descriptors for the open sockets,
otherwise it dies.

=cut
sub open_pipe ($self) {
    bmwqemu::log_call(pipe_prefix => $self->{pipe_prefix});

    sysopen(my $fd_w, $self->{pipe_prefix} . '.in', O_WRONLY)
      or die "Can't open in pipe for writing $!";
    sysopen(my $fd_r, $self->{pipe_prefix} . '.out', O_NONBLOCK | O_RDONLY)
      or die "Can't open out pipe for reading $!";

    my $newsize = $bmwqemu::vars{VIRTIO_CONSOLE_PIPE_SZ} // path('/proc/sys/fs/pipe-max-size')->slurp();
    for my $fd (($fd_w, $fd_r)) {
        my $old = $self->get_pipe_sz($fd) or die("Unable to read PIPE_SZ");
        {
            my $new;
            while ($newsize > $old) {
                $new = $self->set_pipe_sz($fd, $newsize);
                last if ($new);
                $newsize /= 2;
            }
            $new //= $old;
            bmwqemu::fctinfo("Set PIPE_SZ from $old to $new");
        }
    }

    return ($fd_r, $fd_w);
}

sub activate ($self) {
    croak 'VIRTIO_CONSOLE is set 0, so no virtio-serial and virtconsole devices will be available to use with this console'
      unless ($bmwqemu::vars{VIRTIO_CONSOLE} // 1);
    ($self->{fd_read}, $self->{fd_write}) = $self->open_pipe() unless ($self->{fd_read});
    $self->{screen} = consoles::serial_screen::->new($self->{fd_read}, $self->{fd_write});
    $self->{screen}->{carry_buffer} = $self->{preload_buffer};
    $self->{preload_buffer} = '';
    return;
}

sub is_serial_terminal ($self, @) { 1 }

1;

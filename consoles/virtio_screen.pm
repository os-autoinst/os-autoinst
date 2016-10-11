package consoles::virtio_screen;
use 5.018;
use warnings;
use autodie;

sub new {
    my ($class, $socket_fd) = @_;
    my $self = bless({class => $class}, $class);
    $self->{socket_fd} = $socket_fd;
    return $self;
}

sub send_key {
    ...
}

sub hold_key {
    ...
}

sub release_key {
    ...
}

sub type_string {
    ...
}

sub current_screen {
    # TODO: We could generate a bitmap of the terminal text, but I think it would be misleading.
    #       Instead we should use a text terminal viewer in the browser if possible.
    return undef;
}

1;

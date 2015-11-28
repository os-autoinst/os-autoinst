package consoles::ttyConsole;
use base 'consoles::console';
use strict;
use warnings;
require IPC::System::Simple;
use autodie qw(:all);

# to be overloaded
sub trigger_select {
    my ($self) = @_;
    my $key = "ctrl-alt-f" . $self->{args}->{tty};
    $self->screen->send_key({key => $key});
    return;
}

sub screen {
    my ($self) = @_;
    return $self->backend->console('worker');
}

1;

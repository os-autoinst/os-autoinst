package consoles::ssh;
use base 'consoles::console';
use strict;
use warnings;
use testapi qw/get_var/;
require IPC::System::Simple;
use autodie qw(:all);

# no init or activate - this is an abstract class

sub screen {
    my ($self) = @_;
    return $self->{backend}->{consoles}->{worker};
}

sub sshCommand() {
    my ($self, $host) = @_;
    my $sshcommand = "ssh";

    return $sshcommand . " -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root\@$host";
}

sub disable() {
    my ($self) = @_;
    return $self->_kill_window();
}

sub select() {
    my ($self) = @_;
    return $self->_activate_window();
}

1;

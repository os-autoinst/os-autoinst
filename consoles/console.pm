package consoles::console;
use strict;
use warnings;
require IPC::System::Simple;
use autodie qw(:all);

use Class::Accessor "antlers";
has backend => (is => "rw");

sub new {
    my ($class, $testapi_console, $args) = @_;
    my $self = bless({class => $class}, $class);
    $self->{testapi_console} = $testapi_console;
    $self->{args}            = $args;
    $self->{activated}       = 0;
    $self->init;
    return $self;
}

sub init {
    # nothing fancy
}

# SUT was e.g. rebooted
sub reset {
    my ($self) = @_;
    $self->{activated} = 0;
    return;
}

sub screen {
    my ($self) = @_;
    die "screen needs to be implemented in subclasses - $self->{class} does not\n";
    return;
}

# convenince function
sub sshCommand {
    my ($self, $host) = @_;

    return "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root\@$host";
}

# to be overloaded
sub trigger_select {
}

sub select {
    my ($self) = @_;
    my $activated;
    if (!$self->{activated}) {
        $self->activate;
        $activated = 1;
    }
    $self->trigger_select;
    return $activated;
}

sub activate {
    my ($self) = @_;
    $self->{activated} = 1;
    return;
}

1;

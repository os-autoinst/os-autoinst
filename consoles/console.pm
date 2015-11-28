package consoles::console;
use strict;
use warnings;
require IPC::System::Simple;
use autodie qw(:all);

use Class::Accessor "antlers";
has backend => (is => "rw");

use Data::Dumper;
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

sub screen {
    my ($self) = @_;
    die "screen needs to be implemented in subclasses - $self->{class} does not\n";
    return;
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

# common way of selecting the console
sub _activate_window() {
    my ($self) = @_;

    my $display       = $self->display;
    my $new_window_id = $self->{window_id};
    system("DISPLAY=$display xdotool windowactivate --sync $new_window_id");
    return;
}

sub _kill_window() {
    my ($self)    = @_;
    my $window_id = $self->{window_id};
    my $display   = $self->display;
    system("DISPLAY=$display xdotool windowkill $window_id");
    return;
}

# helper function
sub display() {
    my ($self) = @_;

    return $self->console('worker')->{DISPLAY};
}

1;

package consoles::console;
use strict;
use warnings;

sub new {
    my ($class, $backend) = @_;
    my $self = bless({class => $class}, $class);
    $self->{activated} = 0;
    $self->{backend}   = $backend;
    $self->init;
    $backend->{console_classes}->{$self->{name}} = $self;
    return $self;
}

sub screen {
    my ($self) = @_;
    die "screen needs to be implemented in subclasses - $self->{name} does not\n";
    return;
}

sub activate {
    my ($self, $testapi_console, $console_args) = @_;

    $self->{testapi_console} = $testapi_console;
    $self->{activated}       = 1;
    return;
}

# common way of selecting the console
sub _activate_window() {
    my ($self) = @_;

    #CORE::say __FILE__.":".__LINE__.":".bmwqemu::pp($self->{current_console});
    my $display       = $self->display;
    my $new_window_id = $self->{window_id};
    #CORE::say bmwqemu::pp($console_info);
    system("DISPLAY=$display xdotool windowactivate --sync $new_window_id") != -1 || die;
    return;
}

sub _kill_window() {
    my ($self)    = @_;
    my $window_id = $self->{window_id};
    my $display   = $self->display;
    system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
    return;
}

# helper function
sub display() {
    my ($self) = @_;

    return $self->{backend}->{consoles}->{worker}->{DISPLAY};
}

1;

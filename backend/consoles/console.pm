package backend::consoles::console;

sub new {
    my ($class, $backend) = @_;
    my $self = bless({class => $class}, $class);
    $self->{activated} = 0;
    $self->init;
    $backend->{console_classes}->{$self->{name}} = $self;
    return $self;
}

sub activate {
    my ($self, $testapi_console, $console_args) = @_;
    
    return $console_info = {
        # vnc => the vnc for this console
        # window_id => the x11 window id, if applicable
        # DISPLAY => the x11 DISPLAY, if applicable
        # console => the console object (backend::s390x::s3270 or backend::VNC)
    };

}

# common way of selecting the console
sub _activate_window() {
    #CORE::say __FILE__.":".__LINE__.":".bmwqemu::pp($self->{current_console});
    my $display       = $console_info->{DISPLAY};
    my $new_window_id = $console_info->{window_id};
    #CORE::say bmwqemu::pp($console_info);
    system("DISPLAY=$display xdotool windowactivate --sync $new_window_id") != -1 || die;
}

1;

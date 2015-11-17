 elsif ($backend_console eq "remote-window") {
        my ($window_name) = @$console_args;
        # This will only work on a remote X display, i.e. when
        # current_console->{DISPLAY} is set for the current console.
        # There is only one DISPLAY which we can do this with: the
        # local-Xvnc aka worker one
        my $display = $self->{consoles}->{worker}->{DISPLAY};
        # FIXME: verify the first in the list of window ids with the same name is the mothership
        my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
        die if $?;
        $console_info->{window_id} = $window_id;
        $console_info->{DISPLAY}   = $display;
        $console_info->{vnc}       = $self->{consoles}->{worker}->{vnc};
        $console_info->{console}   = $self->{consoles}->{worker}->{vnc};
    }

 sub disable()
    elsif ($backend_console eq "remote-window") {
        my $window_id = $console_info->{window_id};
        my $display   = $self->{consoles}->{worker}->{DISPLAY};
        system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
        $console_info->{console} = undef;
    }
sub select() {
    my ($self) = @_;
    $self->_activate_window();
}

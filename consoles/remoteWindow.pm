use strict;
use warnings;

sub activate() {
    my ($self, $testapi_console, $console_args) = @_;

    my ($window_name) = $console_args->{window_name};
    # This will only work on a remote X display, i.e. when
    # current_console->{DISPLAY} is set for the current console.
    # There is only one DISPLAY which we can do this with: the
    # local-Xvnc aka worker one
    # FIXME: verify the first in the list of window ids with the same name is the mothership
    my $display   = $self->{DISPLAY};
    my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
    die if $?;
    $self->{window_id} = $window_id;
}

sub disable() {
    my ($self)    = @_;
    my $window_id = $self->{window_id};
    my $display   = $self->{consoles}->{worker}->{DISPLAY};
    system("DISPLAY=$display xdotool windowkill $window_id") != -1 || die;
}
sub select() {
    my ($self) = @_;
    $self->_activate_window();
}

1;

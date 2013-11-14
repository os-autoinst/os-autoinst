use base "basetest";
use strict;
use bmwqemu;

# test tomboy: already running
# testcase 1248878

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    # open tomboy
    x11_start_program("tomboy note");
    waitidle;
    $self->check_screen; sleep 2;
    sendkey "alt-f4"; sleep 2;

    # open again
    x11_start_program("tomboy note");
    waitidle;
    $self->check_screen; sleep 2;
    sendkey "alt-f4"; sleep 2;
}

1;

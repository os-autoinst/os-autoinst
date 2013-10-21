use base "basetest";
use strict;
use bmwqemu;

# Install tomboy

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    mouse_hide();
    waitidle;
    ensure_installed("tomboy");
    sleep 60;
    waitidle;
    sleep 90;
    sendkey "esc"; sleep 5;
    waitidle;
    #$self->take_screenshot; 
}

1;

use base "basetest";
use strict;
use bmwqemu;

# log out, check lightdm-gtk-greeter and log in again

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "xfce");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    x11_start_program("xfce4-session-logout");
    sendkey "alt-l";
    sleep 10;
    $self->check_screen;
    sendpassword;
    sendkey "ret";
    sleep 10;
}

1;

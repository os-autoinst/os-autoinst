use base "basetest";
use strict;
use bmwqemu;

# test thunar and open the root directory

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "xfce");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    x11_start_program("thunar");
    sleep 10;
    sendkey "shift-tab";
    sendkey "home";
    sendkey "down";
    $self->check_screen;
    sendkey "alt-f4"; sleep 2;
}

1;

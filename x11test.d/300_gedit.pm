use base "basetest";
use strict;
use bmwqemu;

# test gedit text editor

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    x11_start_program("gedit");
    sendautotype("If you can see this text gedit is working.\n");
    sleep 2;
    $self->check_screen; sleep 2;
    sendkey "alt-f4"; sleep 2;
    sendkey "alt-w"; sleep 2;
}

1;

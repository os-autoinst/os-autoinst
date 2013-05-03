use base "basetest";
use strict;
use bmwqemu;

# test xfce4-terminal

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "xfce");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    mouse_hide(1);
    x11_start_program("xfce4-terminal");
    sleep 2;
    sendkey "ctrl-shift-t";
    for(1..13) { sendkey "ret" }
    sendautotype("echo If you can see this text xfce4-terminal is working.\n");
    sleep 2;
    $self->check_screen;
    sendkey "alt-f4"; sleep 2;
    sendkey "alt-w"; sleep 2; # confirm close of multi-tab window
}

1;

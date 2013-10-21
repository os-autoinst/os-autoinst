use base "basetest";
use strict;
use bmwqemu;

# Test tomboy: Hotkeys
# testcase 1248875

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    # open Hotkeys sheet
    x11_start_program("tomboy note");
    sendkey "alt-e"; sleep 1;
    sendkey "p"; sleep 1;
    sendkey "right"; sleep 1;
    
    # set Hotkeys
    for (1..4){
       sendautotype "\t";
    }
    sendautotype "<Alt>F10\t<Alt>F9";
    $self->check_screen; sleep 2;
    sendkey "esc";    
    waitidle;
    sendkey "alt-f4";

    # logout
    sendkey "alt-f2"; sleep 1;
    sendautotype "gnome-session-quit --logout --force\n"; sleep 20;
    waitidle;

    # login and open tomboy again
    sendkey "ret"; sleep 2;
    waitstillimage;
    sendpassword(); sleep 2;
    sendkey "ret";
    sleep 20; waitidle;
    x11_start_program("tomboy note");

    # test hotkeys
    sendkey "alt-f12"; sleep 1;
    waitidle;
    $self->check_screen; sleep 1;
    sendkey "esc"; sleep 2;

    sendkey "alt-f11"; sleep 1;
    sendkey "up"; sleep 1;
    waitidle;
    $self->check_screen; sleep 1;
    sendkey "ctrl-w"; sleep 2;

    sendkey "alt-f10"; sleep 10;
    waitidle;
    $self->check_screen; sleep 1;
    sendkey "alt-t"; sleep 3;
    sendkey "esc"; sleep 1;
    sendkey "right"; sleep 1;
    sendkey "right"; sleep 1;
    sendkey "right"; sleep 1;
    sendkey "ret"; sleep 3;
    sendkey "alt-d"; sleep 2;

    sendkey "alt-f9";
    sendautotype "sssss\n"; sleep 1;
    $self->check_screen; sleep 1;
    sendkey "ctrl-a"; sleep 1;
    sendkey "delete"; sleep 1;

    # to check all hotkeys
    sendkey "alt-e"; sleep 1;
    sendkey "p"; sleep 1;
    sendkey "right"; sleep 1;
    $self->check_screen; sleep 1;
    sendkey "esc"; sleep 2;
    sendkey "alt-f4"; sleep 2;
}

1;

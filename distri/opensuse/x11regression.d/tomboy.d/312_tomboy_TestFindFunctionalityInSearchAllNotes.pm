use base "basetest";
use strict;
use bmwqemu;

# test tomboy: what links here
# testcase 1248883	

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
    
    # create a note
    sendkey "ctrl-n"; sleep 2;
    sendautotype "hehe"; sleep 1;
    sendkey "alt-f4";
    waitidle;

    sendkey "alt-f9"; sleep 2;
    sendautotype "hehe"; sleep 1;
    $self->check_screen; sleep 2;
    sendkey "alt-f4";
    waitidle;

    # test Edit->preferences
    sendkey "alt-f9"; sleep 2;
    sendkey "alt-e"; sleep 1;
    sendkey "p"; sleep 1;
    $self->check_screen; sleep 2;
    sendkey "alt-f4"; sleep 1;
    sendkey "alt-f4";
    waitidle;

    # test Help->Contents
    sendkey "alt-f9"; sleep 2;
    sendkey "alt-h"; sleep 1;
    sendkey "c"; sleep 1;
    $self->check_screen; sleep 2;
    sendkey "alt-f4"; sleep 1;
    sendkey "alt-f4";
    waitidle;

    # test Help-> About
    sendkey "alt-f9"; sleep 2;
    sendkey "alt-h";
    sendkey "a"; sleep 1;
    $self->check_screen; sleep 2;
    sendkey "alt-f4"; sleep 1;
    sendkey "alt-f4";
    waitidle;

    # test File->Close
    sendkey "alt-f"; sleep 1;
    sendkey "c"; sleep 1;
    $self->check_screen; sleep 2;
    
    # delete the created note
    sendkey "alt-f9"; sleep 1;
    sendkey "up"; sleep 1;
    sendkey "delete"; sleep 1;
    sendkey "alt-d"; sleep 1;
    sendkey "alt-f4";
    waitidle;
}

1;

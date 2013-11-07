use base "basetest";
use strict;
use bmwqemu;

# test tomboy: Test 'undo'/'Redo' feature
# testcase 1248884

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
    
    # create a note type something and undo it
    sendkey "ctrl-n"; sleep 1;
    sendautotype "hehe"; sleep 1;
    sendkey "ctrl-z"; sleep 1;
    $self->check_screen; sleep 1;
    sendautotype "hehe"; sleep 1;
    sendkey "alt-f4";
    waitidle;

    # reopen it and undo again, check the last change still can be undo
    sendkey "alt-f9"; sleep 1;
    sendkey "tab"; sleep 1;
    sendkey "up"; sleep 1;
    sendkey "ret"; sleep 1;
    sendkey "ctrl-z"; sleep 1;
    $self->check_screen; sleep 1;
    sendkey "alt-f4";
    waitidle;

    # Edit not and redo
    sendkey "alt-f9"; sleep 1;
    sendkey "tab"; sleep 1;
    sendkey "up"; sleep 1;
    sendkey "ret"; sleep 1;
    sendautotype "hehe"; sleep 1;
    sendkey "ctrl-z"; sleep 1;
    sendkey "shift-ctrl-z"; sleep 1;
    $self->check_screen; sleep 1;
    sendkey "ctrl-z"; sleep 1;
    sendkey "alt-f4";
    waitidle;

    # Reopen it and redo
    sendkey "alt-f9"; sleep 1;
    sendkey "tab"; sleep 1;
    sendkey "up"; sleep 1;
    sendkey "ret"; sleep 1;
    sendkey "shift-ctrl-z"; sleep 1;
    $self->check_screen; sleep 2;
    sendkey "alt-f4";
    waitidle;
    
    # Delete the note
    sendkey "alt-f9"; sleep 1;
    sendkey "tab"; sleep 1;
    sendkey "up"; sleep 1;
    sendkey "delete"; sleep 1;
    sendkey "alt-d"; sleep 1;
    sendkey "alt-f4";
    waitidle;

    # Kill tomboy note
    x11_start_program("killall -9 tomboy");
    waitidle;
}

1;

use base "basetest";
use strict;
use bmwqemu;

# test tomboy: open
# testcase 1248874

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    # open start note and take screenshot
    x11_start_program("tomboy note");
    sendkey "alt-f11"; sleep 2;
    sendkey "ctrl-home"; sleep 2;
    sendautotype "Rename_"; sleep 1;
    sendkey "ctrl-w"; 
    waitidle;
    
    # Check hotkey for open "start here" still works
    sendkey "alt-fll"; sleep 2;
    waitstillimage;
    checkneedle("tomboy_open_0",5);
    
    sendkey "shift-up"; sleep 2;
    sendkey "delete"; sleep 2;
    sendkey "ctrl-w"; sleep 2;
    sendkey "alt-f4"; sleep 2;

    # logout
    sendkey "alt-f2"; sleep 1;
    sendautotype "gnome-session-quit --logout --force\n"; sleep 20;
    waitidle;
    
    # login
    sendkey "ret"; sleep 2;
    waitstillimage;
    sendpassword(); sleep 2;
    sendkey "ret";
    sleep 20; waitidle; 

    # open start note again and take screenshot
    x11_start_program("tomboy note");
    sendkey "alt-f11"; sleep 2;
    sendkey "up"; sleep 1;
    checkneedle("tomboy_open_1",5);
    sendkey "ctrl-w"; sleep 2;
    sendkey "alt-f4"; sleep 2;
    waitidle;
}

1;

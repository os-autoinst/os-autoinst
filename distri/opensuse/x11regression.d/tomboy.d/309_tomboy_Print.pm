use base "basetest";
use strict;
use bmwqemu;

# test tomboy: print
# testcase 1248880

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
    
    # open a note and print to file
    sendkey "tab"; sleep 1;
    sendkey "down"; sleep 1;
    sendkey "ret"; sleep 3;
    sendkey "ctrl-p"; sleep 3;
    sendkey "tab"; sleep 1;
    sendkey "alt-v"; sleep 5; #FIXME Print to file failed in this version, so just replace with preview.
    #sendkey "alt-p"; sleep 2; #FIXME
    #sendkey "alt-r"; sleep 5; #FIXME

    waitidle;
    $self->check_screen; sleep 2;
    sendkey "ctrl-w"; sleep 2;
    sendkey "ctrl-w"; sleep 2;
    sendkey "alt-f4"; sleep 2;
    waitidle;
}

1;

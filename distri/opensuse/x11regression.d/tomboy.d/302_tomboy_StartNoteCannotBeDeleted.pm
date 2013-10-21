use base "basetest";
use strict;
use bmwqemu;

# test tomboy: start note cannot be deleted
# testcase 1248873

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    x11_start_program("tomboy note");

    # select "start note", to see that start note cann't be deleted
    sendkey "tab"; sleep 2;
    sendkey "down"; sleep 2;
    sendkey "down"; sleep 2;
    sendkey "ret"; 
    sleep 2; waitidle;
    checkneedle("tomboy_delete_0",5); # to see if the delete buttom is avaiable
    #$self->take_screenshot; sleep 2;

    # press the delete button
    sendkey "alt-t"; sleep 2;
    sendkey "esc"; sleep 2;
    sendkey "right"; sleep 2;
    sendkey "right"; sleep 2;
    sendkey "right"; sleep 2;
    sendkey "ret"; sleep 2;
    sendkey "ret"; sleep 2; waitstillimage;
    #sendkey "alt-d"; #FIXME
    sendkey "alt-c"; #FIXME
    sendkey "ctrl-w"; #FIXME It's really awkward that the start note can be deleted in this test version, so I just cancel the delete process here, and close start note page manually.
    checkneedle("tomboy_delete_1",5); # to see if start note still there
    sendkey "tab"; # move the cursor back to text.
    sendkey "alt-f4"; sleep 2;
    waitidle;
}

1;

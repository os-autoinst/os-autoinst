use base "basetest";
use strict;
use bmwqemu;

# test tomboy first run
# testcase 1248872

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    mouse_hide();
    x11_start_program("tomboy note");
    sleep 1;
    # open the menu
    sendkey "alt-f12"; sleep 2;
    waitforneedle("tomboy_menu");
    $self->take_screenshot; sleep 2;
    sendkey "esc";
    sendkey "alt-f4"; sleep 2;
    sendkey "alt-w"; sleep 2;
}

1;

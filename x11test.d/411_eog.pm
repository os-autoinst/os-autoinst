use base "basetest";
use strict;
use bmwqemu;

# test eye of gnome image viewer

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "gnome");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    x11_start_program("eog /usr/share/wallpapers/openSUSEdefault/contents/images/1280x1024.jpg");
    sleep 2;
    $self->check_screen; sleep 2;
    sendkey "alt-f4"; sleep 2;
}

1;

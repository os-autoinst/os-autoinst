use base "basetest";
use strict;
use bmwqemu;

# test xfce4-appfinder, auto-completion and starting xfce4-about

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "xfce");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    sendkey "alt-f2";
    sleep 2;
    sendkey "down";
    sendautotype "about\n";
    $self->take_screenshot;
    sendkeyw "ret";
    $self->take_screenshot;
    sendkey "alt-f4"; sleep 2;
}

1;

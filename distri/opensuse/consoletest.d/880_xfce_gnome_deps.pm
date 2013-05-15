use base "basetest";
use strict;
use bmwqemu;

# show installed GNOME components, allows to look for possibly unwanted
# dependencies

# this function decides if the test shall run
sub is_applicable
{
    return($ENV{DESKTOP} eq "xfce");
}

# this part contains the steps to run this test
sub run()
{
    my $self=shift;
    script_run('rpm -qa "*nautilus*|*gnome*" | sort | tee /tmp/xfce-gnome-deps');
    script_sudo('mv /tmp/xfce-gnome-deps /var/log');
}

1;

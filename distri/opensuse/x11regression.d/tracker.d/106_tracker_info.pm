use base "basetest";
use bmwqemu;

# Case 1248741 - Beagle: beagle text filter extracts content
# Modify to : Tracker - tracker info for files

sub is_applicable()
{
        return $ENV{DESKTOP}=~/kde|gnome/;
}

sub run()
{
        my $self=shift;
        x11_start_program("xterm");
        sleep 2; waitidle;
        $self->check_screen;
        sendautotype("cd\n");
        sendautotype("tracker-info newpl.pl\n");
        sleep 2; waitstillimage;
        $self->check_screen;
        sendkey "alt-f4"; sleep 2; #close xterm
        #$self->check_screen;
}

1;

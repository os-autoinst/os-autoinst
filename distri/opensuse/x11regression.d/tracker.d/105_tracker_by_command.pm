use base "basetest";
use bmwqemu;

# Case 1248747 - Beagle: beagled starts
# Modify to : Tracker - tracker search from the command line. tracker-search starts

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
        sendautotype("tracker-search newfile\n");
        sleep 2; waitstillimage;
        $self->check_screen;
        sendkey "alt-f4"; sleep 2; #close xterm
#       $self->check_screen;
}

1;

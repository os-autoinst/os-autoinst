use base "basetest";
use bmwqemu;

# Case 1248739 - Beagle: beagle-search starts
# Modify to : Tracker: tracker-needle starts

sub is_applicable()
{
        return $ENV{DESKTOP}=~/kde|gnome/;
}

sub run()
{
        my $self=shift;
        x11_start_program("tracker-needle");
        sleep 2; waitidle;
        $self->check_screen;
        sendkey "alt-f4"; sleep 2;
        #$self->check_screen;
}


1;

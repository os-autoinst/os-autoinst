use base "basetest";
use bmwqemu;

# Case 1248740 - Beagle: beagle-settings starts
# Modify to : Tracker: tracker-preferences starts

sub is_applicable()
{
        return $ENV{DESKTOP}=~/kde|gnome/;
}

sub run()
{
        my $self=shift;
        x11_start_program("tracker-preferences");
        sleep 2; waitidle; 
        $self->check_screen;
        sendkey "alt-f4"; sleep 2;
        #$self->check_screen;
}

sub checklist()
{
        # return hashref:
        return {qw(
        )}
}

1;

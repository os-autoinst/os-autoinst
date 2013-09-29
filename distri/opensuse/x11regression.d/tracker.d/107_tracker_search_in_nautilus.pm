use base "basetest";
use bmwqemu;

# Case 1248746 - Beagle: Find a file with Search in Nautilus
# Modify to : Tracker - Find a file with Search in Nautilus

sub is_applicable()
{
        return $ENV{DESKTOP}=~/kde|gnome/;
}

sub run()
{
        my $self=shift;
        x11_start_program("nautilus");
        sleep 2; waitidle; 
        $self->check_screen;
        sendkey "ctrl-f";
        sleep 2;
        sendautotype("newfile");
        sendkey "ret";
        sleep 2;waitidle;
        $self->check_screen;  # should open file newfile
        sendautotype("Hello world.\n");
        sleep 2; 
        sendkey "ctrl-s";
        sleep 2; waitstillimage;
        $self->check_screen;
        sendkey "alt-f4"; sleep 2; #close gedit
        $self->check_screen;
        sendkey "alt-f4"; sleep 2; #close nautilus
}


1;

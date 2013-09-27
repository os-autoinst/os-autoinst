use base "basetest";
use bmwqemu;

# Case 1248738 - Beagle: Search all data with beagle-search
# Modify to : Tracker: Seach all date with tracker-needle

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
	sendautotype("newfile");
	sleep 2; waitstillimage;
	$self->check_screen;
	sendkey "alt-f4"; sleep 2;
	#$self->check_screen;
}


1;

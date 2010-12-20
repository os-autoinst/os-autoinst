use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome" && !$ENV{LIVECD};
}

sub run()
{
	my $self=shift;
	x11_start_program("banshee-1");
	$self->take_screenshot;
	sendkey "ctrl-q"; # really quit (alt-f4 just backgrounds)
	sendkey "alt-f4"; 
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
		055ef0f7abcff0ebf91f545ce290ef9a OK
	)}
}

1;

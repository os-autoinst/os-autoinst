use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	x11_start_program("amarok");
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 3; # mp3 popup
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 3; # close kwallet popup
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 9; # close another popup
	$self->take_screenshot;
	sendkey "ctrl-q"; # really quit (alt-f4 just backgrounds)
}

sub checklist()
{
	# return hashref:
	# bad: has random bits in pixels at (68,67-69)
	return {qw(
		efc74946144a6260943d4383a972dafb OK
		37834e420389f2a96e896d520010c629 OK
	)}
}

1;

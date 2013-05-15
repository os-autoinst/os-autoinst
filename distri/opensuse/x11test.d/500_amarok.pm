use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	ensure_installed("amarok");
	x11_start_program("amarok /usr/share/sounds/alsa/test.wav");
	waitidle;
	$self->check_screen;
	sendkey "alt-f4"; sleep 3; # amazon store country popup
	$self->check_screen;
	sendkey "alt-d"; sendkeyw "alt-n"; # mp3 popup
#	sendkey "alt-f4"; sleep 3; # close kwallet popup
	$self->check_screen;
	sendkeyw "alt-y"; # use music path as collection folder
	$self->check_screen;
	sendkey "ctrl-q"; # really quit (alt-f4 just backgrounds)
	sleep 2; waitidle;
	x11_start_program("killall amarok") unless $ENV{NICEVIDEO}; # to be sure that it does not interfere with later tests
}

1;

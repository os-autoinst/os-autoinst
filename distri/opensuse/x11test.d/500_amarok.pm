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
	$self->start_audiocapture;
	x11_start_program("amarok http://openqa.opensuse.org/opensuse/audio/bar.oga");
	sleep 3;
	$self->check_DTMF('123A456B789C*0#D');
	sleep 2;
	$self->check_screen;
	sendkeyw "alt-y"; # use music path as collection folder
	$self->check_screen;
	sendkey "ctrl-q"; # really quit (alt-f4 just backgrounds)
	sleep 2; waitidle;
	x11_start_program("killall amarok") unless $ENV{NICEVIDEO}; # to be sure that it does not interfere with later tests
}

1;

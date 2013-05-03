use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO};# && $ENV{BIGTEST};
}

sub run()
{
	my $self=shift;
	$self->start_audiocapture;
	x11_start_program("firefox http://openqa.opensuse.org/opensuse/audio/bar.oga");
	sleep 3;
	$self->stop_audiocapture;
	$self->check_screen;
	sendkey "alt-f4"; sleep 2;
	sendkeyw "ret"; # confirm "save&quit"
}

sub wav_checklist()
{
	# return hashref:
	return {
		1=>'123A456B789C*0#D'
	};
}


1;

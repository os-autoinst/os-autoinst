use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	script_run('wget openqa.opensuse.org/opensuse/audio/bar.wav');
	$self->take_screenshot;
	$self->start_audiocapture;
	script_run('aplay bar.wav');
	$self->stop_audiocapture;
}

sub wav_checklist()
{
	# return hashref:
	return {
		1=>'123A456B789C*0#D'
	};
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;

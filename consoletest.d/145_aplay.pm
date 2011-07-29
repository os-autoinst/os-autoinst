use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	$self->start_audiocapture;
	script_run('wget upload.kruton.de/files/1311770853/bar.wav');
	$self->take_screenshot;
	sleep 2;
	script_run('aplay bar.wav');
	$self->take_screenshot;
	$self->stop_audiocapture;
	sleep 2;
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

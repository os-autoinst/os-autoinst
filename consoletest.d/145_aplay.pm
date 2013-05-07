use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	script_sudo("zypper -n in alsa-utils");
	script_run('cd /tmp;wget openqa.opensuse.org/opensuse/audio/bar.wav');
	$self->check_screen;
	$self->start_audiocapture;
	script_run("aplay bar.wav ; echo aplay_finished > /dev/$serialdev");
	waitserial('aplay_finished');
	$self->check_DTMF('123A456B789C*0#D');
}

1;

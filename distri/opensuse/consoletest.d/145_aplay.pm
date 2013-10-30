use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	script_run("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	sleep 2;
	script_sudo("zypper -n in alsa-utils");
	script_run("cd /tmp;wget openqa.opensuse.org/opensuse/audio/bar.wav");
	$self->check_screen;
	script_run('clear');
	script_run('set_default_volume -f');
	$self->start_audiocapture;
	script_run("aplay bar.wav ; echo aplay_finished > /dev/$serialdev");
	waitserial('aplay_finished');
	$self->take_screenshot;
	$self->check_DTMF('123A456B789C*0#D');
	script_run('alsamixer');
	sleep 1;
	$self->check_screen;
	$self->sendkey('esc');
	$self->sendkey('esc');
}

1;

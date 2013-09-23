use base "basetest";
use bmwqemu;

sub run() {
	my $self=shift;

	# cleanup
	script_sudo_logout;
	sleep 2;
	sendkey "ctrl-d"; # logout
	sleep 2;

	if (checkEnv("DESKTOP", "textmode")) {
	    sendkey "ctrl-alt-f1"; # go back to first console
	} else {
	    sendkey "ctrl-alt-f7"; # go back to X11
	    sleep 2;
	    sendkey "backspace"; # deactivate blanking
	    sleep 2;
	    if (checkneedle("screenlock")) {
		if (checkEnv("DESKTOP", "gnome")) {
		    sendkey "esc";
		    sleep 1;
		}
		sendpassword;
		sendkey "ret";
	    }

	    # workaround for bug 834165. Apper should not try to
	    # refresh repos when the console is not active:
	    if (checkneedle("apper-refresh-popup-bnc834165")) {
		    ++$self->{dents};
		    sendkey 'alt-c';
		    sleep 30;
	    }
	    mouse_hide(1);
	}
	waitidle;
	$self->check_screen();
}

sub test_flags() {
        return {'milestone' => 1, 'fatal' => 1, 'important' => 1};
}


1;

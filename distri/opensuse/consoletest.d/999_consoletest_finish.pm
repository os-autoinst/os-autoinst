use base "basetest";
use bmwqemu;

sub run() {
	# cleanup
	script_sudo_logout;
	sleep 2;
	sendkey "ctrl-d"; # logout
	sleep 2;

	sendkey "ctrl-alt-f7"; # go back to X11
	sleep 2;
	sendkey "backspace"; # deactivate blanking
	sleep 2;
	waitidle;
	$self->check_screen();
}

sub test_flags() {
        return {'milestone' => 1, 'fatal' => 1, 'important' => 1};
}


1;

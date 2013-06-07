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
}

sub test_class($) {
        return basetest::FATAL_IMPORTANT_TEST;
}


1;

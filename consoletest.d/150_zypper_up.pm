package zypper_up;
use base "basetest";
use bmwqemu;
sub run()
{
	script_sudo("zypper -n -q up");
	waitidle 60;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_sudo("zypper -n -q up");
	waitidle;
	script_run('echo $?');
}

sub checklist()
{
	# return hashref:
	return {qw(
		62ba0ecc2c42cdfa091a703e0396bebf OK
		65e3634bd721ba2b8f6779f6e4a114f5 OK
	)}
}

1;

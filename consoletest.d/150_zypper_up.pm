package zypper_up;
use base "basetest";
use bmwqemu;
sub run()
{
	script_sudo("zypper -n -q up");
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
		62ba0ecc2c42cdfa091a703e0396bebf OK
	)}
}

1;

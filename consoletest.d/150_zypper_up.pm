package zypper_up;
use base "basetest";
use bmwqemu;
sub run()
{
	script_sudo("zypper -n -q up");
	waitidle;
}

1;

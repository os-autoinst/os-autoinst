use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
	return $ENV{ZDUP} || $ENV{WDUP};
}

sub run()
{
	# reboot after dup
	sendkey "ctrl-alt-delete";
	script_sudo_logout;
	sleep 50;
}

1;

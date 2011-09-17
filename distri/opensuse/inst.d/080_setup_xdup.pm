use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
	return $ENV{ZDUP} || $ENV{WDUP};
}

sub run()
{
	# wait booted
	sleep 30; waitidle;
	# log into text console
	sendkey "ctrl-alt-f4";
	sleep 2;
	sendautotype "$username\n";
	sleep 2;
	sendpassword; sendautotype "\n";
	sleep 3;
	sendautotype "PS1=\$\n"; # set constant shell promt
	sleep 1;
}

1;

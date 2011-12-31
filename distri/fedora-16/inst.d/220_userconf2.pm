use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	# creating non-root user here
	sendautotype "$realname\t";
	sendautotype "$username\t";
	sendautotype " \t"; # add to admin group
	sleep 2;
	sendautotype "$password\t"; # user PW
	sendautotype "$password";
	sendkey "alt-f"; # forward
	waitidle;
}

1;

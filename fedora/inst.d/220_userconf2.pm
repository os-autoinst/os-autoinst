use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	# creating non-root user here
	sendautotype "$username\t";
	sleep 2;
	sendautotype "$realname\t";
	sendautotype "$password\t"; # user PW
	sendautotype "$password";
	sendkey "alt-f"; # forward
	waitidle;
	sendkey "alt-y"; # use weak PW
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(90);
	sendautotype "$password\n"; # root PW
	sendautotype "$password\n"; # root PW
	sendautotype "$realname\n"; # real name
	sendkey "ret"; # username
	sendautotype "$password\n"; # user PW
	sendautotype "$password\n"; # user PW
}

1;

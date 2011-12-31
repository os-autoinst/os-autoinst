use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendautotype "$password\t"; # root PW
	sendautotype "$password"; # root PW
	sendkey "alt-n"; # username
	waitidle;
	sendkey "alt-u"; # use weak PW
}

1;

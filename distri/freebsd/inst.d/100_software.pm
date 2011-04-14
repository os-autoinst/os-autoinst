use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "6"; # average user
	sendkey "spc"; # select
	sleep 1;
	sendkey "ret"; # Exit
	sleep 1;
	sendkey "tab"; # say No
	sendkey "ret"; # to FreeBSD ports collection
	sleep 1;
	sendkey "x"; # Exit
	sleep 1;
	sendkey "ret"; # Exit
	sleep 1;
	sendkey "ret"; # Install media CD
	sleep 1;
	sendkey "ret"; # Confirm Install
}

1;

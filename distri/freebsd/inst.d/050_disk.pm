use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "ret"; # fdisk help text
	sendkey "a"; # entire disk
	sendkey "q"; # done
	sendkey "ret"; # boot manager
	sendkey "ret"; # another fdisk help text
	sleep 1;

	sendkey "c"; # create part
	for(1..9) { sendkey "backspace" }
	sendautotype "6g\n"; # GB size
	sendkey "ret"; # FS
	sendautotype "/\n"; # mountpoint
	sleep 2;

	sendkey "c"; # create part
	sendkey "ret"; # confirm size
	sendkey "down"; # select swap
	sendkey "ret";

	sendkey "q"; # finish
}

1;

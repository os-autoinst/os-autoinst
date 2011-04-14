use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	if($ENV{NOTIMEZONE}) { sendkey "tab" }
	else {
	# config timezone ret tab ret 8 ret 6 # dont conf 8=Europe 6=Belgium ret 
		sendkey "ret";
		sendkey "tab";
		sendkey "ret";
		sendkey "8";	# Europe
		sendkey "ret";
		sendkey "6";	# Belgium
		sleep 2;
		sendkey "ret";
	}
	sendkey "ret"; # done
}

1;

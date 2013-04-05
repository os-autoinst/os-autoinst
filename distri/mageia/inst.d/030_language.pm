use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 30;
#	waitidle();
	waitstillimage(10,100);
#	waitinststage("mageia-language", 100);
#	avgcolor=0.684,0.714,0.733
	sendkey "end";
	sendkey "ret";
	sendkey "down";
	sendkey "down";
	sendkey "tab"; # skip media check
	sendkey "tab"; # skip media check
	sendkey "tab"; # skip media check
	sendkey "ret";
}

1;

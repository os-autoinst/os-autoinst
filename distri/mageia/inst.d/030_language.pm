use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	sleep 30;
#	waitidle();
	waitstillimage(10,100);
	mouse_hide();
	sleep 1;
	waitgoodimage(30);
#	avgcolor=0.684,0.714,0.733
	sendkey "end"; # Go to bottom of list
	sendkey "ret"; # Expand "Oceania/Pacific
	sendkey "down"; # Select English (Australia)
	sendkey "down"; # Select Enlgish (New Zealand)
	sendkey "tab"; # Select Multiple languages
	sendkey "tab"; # Select help
	sendkey "tab"; # Select Next
	sendkey "ret"; # push next button
}

1;

use base "installstep";
use strict;
use bmwqemu;

sub run()
{
#	while () {
#	sleep 10;
#	mouse_hide();
#        };
	waitidle(30);
	waitstillimage(10,300);
	mouse_set(10,10);
	mouse_hide(1);
	sleep 1;
	waitinststage('mageia4-lang',3000);
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

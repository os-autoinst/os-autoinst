use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitstillimage(10,20);
        sendkey "tab"; 
	sendkey "ret";
	waitstillimage(10,20);
        sendkey "tab"; 
        sendkey "tab"; 
	sendkey "ret";


}

1;

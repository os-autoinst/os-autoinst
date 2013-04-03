use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitstillimage(5,20);
        sendkey "tab"; 
	sendkey "ret";


}

1;

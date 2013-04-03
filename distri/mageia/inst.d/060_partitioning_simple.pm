use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitstillimage(3,20);
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";


}

1;

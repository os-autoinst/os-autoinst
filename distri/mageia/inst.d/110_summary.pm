use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(10);
	waitstillimage(60,290);

        sendkey "shift-tab"; # skip media check
	sendkey "ret";


}

1;

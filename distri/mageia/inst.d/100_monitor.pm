use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	if($ENV{DESKTOP}=~/kde/) {
	waitidle(10);
	waitstillimage(10,20);

        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";
	}

}

1;

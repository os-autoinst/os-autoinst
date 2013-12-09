use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	if($ENV{DESKTOP}=~/kde/) {
	waitidle(30);
	waitstillimage(30,200);

        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";
	}

}

1;

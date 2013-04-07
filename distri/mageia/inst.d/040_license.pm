use base "installstep";
use strict;
use bmwqemu;

sub run()
{
#	waitstillimage(50,100);
	waitidle(5);
        sendkey "up";
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";


}

1;

use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(10);
	waitstillimage(30,200);

        sendkey "down"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";


}

1;

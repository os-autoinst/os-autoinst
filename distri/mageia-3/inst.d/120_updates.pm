use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(30);
	waitstillimage(30,200);

        sendkey "down"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";


}

1;

use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitstillimage(5,20);
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";


}

1;

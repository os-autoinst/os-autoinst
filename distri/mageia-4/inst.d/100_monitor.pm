use base "installstep";
use strict;
use bmwqemu;

sub run()
{
        mouse_set(10,10);
        mouse_hide(1);
        sleep 1;
	unless($ENV{DESKTOP}=~/none/) {
	waitidle(30);
	waitstillimage(30,200);

        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";
	}

}

1;

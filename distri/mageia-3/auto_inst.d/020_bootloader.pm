use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	# boot
	sendkey "f6";
	sleep 1;
	sendkey "ret";
        sleep 2;
	sendautotype "auto_install=floppy";
        sleep 2;
	sendkey "ret";
}

1;

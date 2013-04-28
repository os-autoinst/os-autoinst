use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	# boot
	sendkey "ret";  # push enter on default (intall)
}

1;

use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	# boot
	sendkey "ret";
}

1;

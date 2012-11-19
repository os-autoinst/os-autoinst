use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	# skip media check
	sendkeyw $cmd{"next"};
}

1;

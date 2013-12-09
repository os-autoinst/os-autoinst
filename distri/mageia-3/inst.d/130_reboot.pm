use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(30);
	waitstillimage(40,200);

	sendkey "ret";


}

1;

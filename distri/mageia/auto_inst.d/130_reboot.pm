use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(100);
	waitstillimage(100,3000);

	sendkey "ret";


}

1;

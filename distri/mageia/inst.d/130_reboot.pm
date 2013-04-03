use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(10);
	waitstillimage(10,20);

	sendkey "ret";


}

1;

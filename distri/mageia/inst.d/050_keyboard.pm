use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitstillimage(5,20);
        sendkey "tab"; # highlight keyboard list, leave default
        sendkey "tab"; # more
        sendkey "tab"; # help
        sendkey "tab"; # next button
	sendkey "ret"; # push next button


}

1;

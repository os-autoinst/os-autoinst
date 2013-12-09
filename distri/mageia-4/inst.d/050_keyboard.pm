use base "installstep";
use strict;
use bmwqemu;

sub run()
{
       mouse_set(10,10);
       mouse_hide(1);
       sleep 1;
	waitidle(20);
	waitstillimage(20,2000);
        sendkey "tab"; # highlight keyboard list, leave default
        sendkey "tab"; # more
        sendkey "tab"; # help
        sendkey "tab"; # next button
	sendkey "ret"; # push next button


}

1;

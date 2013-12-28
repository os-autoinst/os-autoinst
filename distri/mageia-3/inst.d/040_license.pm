use base "installstep";
use strict;
use bmwqemu;

sub run()
{
#	waitstillimage(50,100);
	waitidle(30);
        sendkey "up";  # select "Accept"
        sendkey "tab"; # highlight release notes
        sendkey "tab"; # highlight help
        sendkey "tab"; # highlight quit
        sendkey "tab"; # highlight next
	sendkey "ret"; # push next button


}

1;

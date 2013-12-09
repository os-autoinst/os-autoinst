use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(50);
	waitstillimage(60,3600);
	mouse_hide();
	waitinststage ("mageia-setupusers1",100);
#	waitgoodimage(1200);
        sendautotype "$password\t"; # root PW
	sleep 1;
        sendautotype "$password"; # root PW
	sleep 1;

	unless ($ENV{DESKTOP}=~/none/) {
        sendkey "tab"; # User icon
	sleep 1;
	}
        sendkey "tab"; # skip media check
	sleep 1;
        sendautotype "$realname\t"; # Test user
	sleep 1;
        sendautotype "$username\t"; # Test user
	sleep 1;
        sendautotype "$password\t"; # root PW
	sleep 1;
        sendautotype "$password"; # root PW
	sleep 1;
        sendkey "tab"; # skip media check
	sleep 1;
        sendkey "tab"; # skip media check
	sleep 1;
	sendkey "tab"; # skip media check
	sleep 1;
	sendkey "ret";


}

1;

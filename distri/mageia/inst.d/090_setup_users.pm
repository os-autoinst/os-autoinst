use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(15000);
#	waitstillimage(60,3600);
	mouse_hide();
	waitintstage ("mageia-setupusers1",300);
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

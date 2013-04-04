use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(15000);
	waitstillimage(60,3600);
        sendautotype "$password\t"; # root PW
        sendautotype "$password"; # root PW

        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendautotype "QA Test\t"; # Test user
        sendautotype "test\t"; # Test user
        sendautotype "$password\t"; # root PW
        sendautotype "$password"; # root PW

        sendkey "tab"; # skip media check
	sleep 1;
        sendkey "tab"; # skip media check
	sleep 1;
	sendkey "tab"; # skip media check
	sleep 1;
	sendkey "ret";


}

1;

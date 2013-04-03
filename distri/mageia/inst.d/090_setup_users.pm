use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle(10);
	waitstillimage(10,20);
        sendautotype "$password\t"; # root PW
        sendautotype "$password"; # root PW

        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendautotype "QA Test\t"; # Test user
        sendautotype "test\t"; # Test user
        sendautotype "$password\t"; # root PW
        sendautotype "$password\t"; # root PW

        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
        sendkey "tab"; # skip media check
	sendkey "ret";


}

1;

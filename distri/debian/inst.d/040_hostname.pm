use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sleep 25; waitstillimage(12,90); # DHCP
	sendkey "ret"; # hostname
	sendautotype "zq1.de\n"; # domainname
}

1;

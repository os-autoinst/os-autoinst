use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendautotype "fedoratest.zq1.de\n"; # host+domainname
}

1;

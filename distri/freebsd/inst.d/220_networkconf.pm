use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	sendkey "ret"; # configure Ethernet
	sleep 3;
	sendkey "ret"; # select first eth dev
	sleep 3;
	sendkey "ret"; # no IPv6
	sleep 3;
	sendkey "tab"; # use DHCP
	sleep 3;
	sendkey "ret";
	sleep 10; # config takes some time
	sendautotype "freebsdtest\t";
	sendautotype "zq1.de\t";
#	sendautotype "10.0.2.2\t"; # IP
#	sendautotype "10.0.2.3\t"; # DNS
	sendautotype "\t\t\t\t\t";
	sleep 3;
	sendkey "ret"; # confirm net conf
	sleep 3;
	sendkey "ret"; # not a router
	sleep 3;
}

1;

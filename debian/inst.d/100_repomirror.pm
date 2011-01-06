use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	{
		local $ENV{SCREENSHOTINTERVAL}=5;
		waitinststage("debian-mirrorselection", 900);
	}
	sendautotype "g\n"; # Configure the package manager (country=Germany)
	sendkey "ret"; # use first mirror
	if($ENV{HTTPPROXY}) {
		# this needs qemu>=0.13 for colons or
		# http://www.mail-archive.com/qemu-devel@nongnu.org/msg34190.htm
		sendautotype "http://$ENV{HTTPPROXY}/\n"; # proxy
	} else {
		sendkey "ret"; # no proxy
	}
}

1;

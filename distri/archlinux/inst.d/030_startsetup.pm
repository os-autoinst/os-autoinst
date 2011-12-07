use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	waitidle(25); # boot up
	waitstillimage;
	if($ENV{HTTPPROXY}) {
		sendautotype "export http_proxy=http://$ENV{HTTPPROXY}/\n";
	}
	sendautotype "/arch/setup\n"; # start install
	waitidle(10); # starting setup
	waitstillimage;
	sendkey "ret"; # close info box
}

1;

use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "7"; # config
	sleep 1;
	sendkeyw "ret"; # ok

	sendkey "r"; # root passwd
	sleep 1;
	sendkey "ret"; # ok
	sleep 1;
	for (1..2) {
		sendpassword;
		sendkey "ret";
	}
	sleep 1;
	
	sendkey "d"; # done
	sendkey "ret"; # back
	waitstillimage(10,60);
}

1;

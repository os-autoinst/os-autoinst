use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	# boot
	sleep 1;
	sendkey "ret";
	qemusend "boot_set c"; # boot from HDD next time
}

1;

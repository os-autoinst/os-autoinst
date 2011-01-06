use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	set_hash_rects(
        [412,284,200,200], # center of 1024x768
        );
	local $ENV{SCREENSHOTINTERVAL}=5;
	waitinststage("installationcomplete", 2400);
	waitidle;
	sendkey "alt-r"; # reboot
	sleep 30; # time to boot into CD's bootloader again
	qemusend "eject -f ide1-cd0"; # force eject
	sleep 1;
	qemusend "system_reset";
}

1;

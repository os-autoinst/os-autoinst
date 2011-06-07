#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;

sub run()
{
	waitinststage("welcome", 290);

	if(0 && $ENV{BETA} && !$ENV{LIVECD}) {
		# ack beta message
		sendkey "ret";
		#sendkey $cmd{acceptlicense};
	}

	# animated cursor wastes disk space, so it is moved to bottom right corner
	mousemove_raw(0x7fff,0x7fff); 
	mousemove_raw(0x7fff,0x7fff); # work around no reaction first time
	sendkey "alt-o"; # beta warning
	waitidle;
	# license+lang
	sendkey $cmd{"accept"}; # accept license
	waitidle;
	sendkey $cmd{"next"};
}

1;

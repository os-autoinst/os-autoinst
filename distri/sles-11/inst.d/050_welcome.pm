#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	my $self=shift;
        
	my $ret = waitforneedle("inst-welcome", 350);
	sendkey "ret";

	# animated cursor wastes disk space, so it is moved to bottom right corner
	mouse_hide;

	waitidle;
	# license+lang
	if($ENV{HASLICENSE}) {
		sendkey $cmd{"accept"}; # accept license
	}
	waitforneedle("languagepicked", 2);
	sendkey $cmd{"next"};
}

1;

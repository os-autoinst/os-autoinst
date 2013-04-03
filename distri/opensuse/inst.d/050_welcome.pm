#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitforneedle("inst-welcome", 150);

	# animated cursor wastes disk space, so it is moved to bottom right corner
	mouse_hide;
	#sendkey "alt-o"; # beta warning
	#  TODO make the beta warning check more clever
	waitidle;
	# license+lang
	if($ENV{HASLICENSE}) {
		sendkey $cmd{"accept"}; # accept license
	}
	waitforneedle("languagepicked", 2);
	sendkey $cmd{"next"};
	if (checkneedle("langincomplete", 1)) {
	    sendkey "alt-f";
        }
}

1;

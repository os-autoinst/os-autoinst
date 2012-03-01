#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitstillimage(12, 290);

	# animated cursor wastes disk space, so it is moved to bottom right corner
	mousemove_raw(0x7fff,0x7fff); 
	mousemove_raw(0x7fff,0x7fff); # work around no reaction first time
	$self->take_screenshot;
	sendkey "alt-o"; # beta warning
	waitidle;
	# license+lang
	if($ENV{HASLICENSE}) {
		sendkey $cmd{"accept"}; # accept license
	}
	waitidle;
	sendkey $cmd{"next"};
	sleep 2;sendkey "alt-f"; # continue on incomplete lang warning
}

1;

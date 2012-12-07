#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitstillimage(22, 290);

	# animated cursor wastes disk space, so it is moved to bottom right corner
	mouse_hide;
	$self->take_screenshot;
	sendkey "alt-o"; # beta warning
	waitidle;
	# license+lang
	if($ENV{HASLICENSE}) {
		sendkey $cmd{"accept"}; # accept license
	}
	waitidle;
	$self->take_screenshot; sleep 1;
	sendkey $cmd{"next"};
	sleep 2;sendkey "alt-f"; # continue on incomplete lang warning
}

1;

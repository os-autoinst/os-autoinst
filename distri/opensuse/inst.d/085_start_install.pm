#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	my $self=shift;
	# start install
	sendkey $cmd{install};
	sleep 2;
	waitidle 5;
	# confirm
	$self->take_screenshot;
	sendkey $cmd{install};
	waitinststage "performinstallation";
	if(!$ENV{LIVECD} && !$ENV{NICEVIDEO}) {
		sleep 5; # view installation details
		sendkey $cmd{instdetails};
	}
}

1;

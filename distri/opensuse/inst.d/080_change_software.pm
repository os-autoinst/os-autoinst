#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
	my $self=shift;
	return $self->SUPER::is_applicable && !$ENV{LIVECD};
}

sub run()
{
	my $self=shift;
	if($ENV{DOCRUN} || waitimage("software-conflict-*",9)) {
		sendkey $cmd{change};	# Change
		sendkey $cmd{software};	# Software
		waitidle;
		for(1..3) {
			sendkey "down";
		}
		sleep 4;
		$self->take_screenshot;
		sendkey $cmd{accept}; # Accept
		sleep 2;
		sendkey "alt-o"; # cOntinue
		waitidle;
	}
}

1;

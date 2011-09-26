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
	# autoconf phase
	# includes downloads, so waitidle is bad.
	waitstillimage(12,120);
	#waitidle 29;
	# Installation Mode = new Installation
	if($ENV{UPGRADE}) {
		sendkey "alt-u";
	}
	if($ENV{ADDONURL}) {
		sendkey "alt-c"; # Include Add-On Products
	}
	$self->take_screenshot;
	sendkeyw $cmd{"next"};
}

1;

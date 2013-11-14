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
	waitforneedle("inst-instmode", 120);
	# Installation Mode = new Installation or Upgrade
	if($ENV{UPGRADE}) {
		sendkeyw $cmd{"update"};
		sendkeyw $cmd{"next"};
		waitforneedle("select-for-update", 10);
	} else {
		if($ENV{ADDONURL}) {
			sendkey "alt-c"; # Include Add-On Products
			waitforneedle("addonproduct-included", 10);
		}
		if($ENV{AUTOCONF}) {
			sendkey "alt-s"; # toggle automatic configuration
			waitforneedle("autoconf-deselected", 10);
		}
	    	sendkeyw $cmd{"next"};
		waitforneedle("inst-timezone", 30) || die 'no timezone';
	}
}

1;

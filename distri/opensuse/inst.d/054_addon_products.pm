#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
  	my $self=shift;
	return $self->SUPER::is_applicable && !$ENV{LIVECD} && $ENV{ADDONURL};
}

sub run()
{
	my $self=shift;
	if($ENV{VIDEOMODE} && $ENV{VIDEOMODE} eq "text") {$cmd{xnext}="alt-x"}
	if(!$ENV{NET} && !$ENV{DUD}) {
		sendkeyw $cmd{"next"}; # use network
		sendkeyw "alt-o"; # OK DHCP network
	}
	my $repo=0;
	$repo++ if $ENV{DUD};
	foreach my $url (split(/\+/, $ENV{ADDONURL})) {
		if($repo++) {sendkeyw "alt-a"; } # Add another
		sendkeyw $cmd{"xnext"}; # Specify URL (default)
		sendautotype($url);
		sendkeyw $cmd{"next"};
		sendkey "alt-i";sendkeyw "alt-t"; # confirm import (trust) key
	}
	$self->take_screenshot;
	sendkeyw $cmd{"next"}; # done
}

1;

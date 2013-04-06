#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub is_applicable()
{
  	my $self=shift;
	return $self->SUPER::is_applicable && $ENV{DVD} && $ENV{NOIMAGES};
}

sub run()
{
	sendkey $cmd{change};	# Change
	sleep 3;
	my $images=($ENV{VIDEOMODE} eq "text")?"alt-i":"i";
	sendkey $images;        # Images
	sleep 10;
}

1;

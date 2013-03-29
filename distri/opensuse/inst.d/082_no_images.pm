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
	waitforneedle("inst-using-images", 1);
	sendkey $cmd{change};	# Change
	my $images=($ENV{VIDEOMODE} eq "text")?"alt-i":"i";
	sendkey $images;        # Images
	waitforneedle("inst-not-using-images", 1);
}

1;

#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	# overview-generation
	waitstillimage();
	waitidle 10;
}

1;

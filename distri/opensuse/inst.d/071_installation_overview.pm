#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	# overview-generation
	# this is almost impossible to check for real
	waitforneedle("inst-overview", 10);
	# preserve it for the video
	waitidle 10;
}

1;

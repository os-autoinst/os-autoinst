#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	# overview-generation
	waitinststage "installationoverview";
	sleep 5;
	waitidle 10;
}

1;

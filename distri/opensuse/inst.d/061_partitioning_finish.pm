#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitinststage "disk";
	sleep 2;
	sendkey $cmd{"next"};
}

1;

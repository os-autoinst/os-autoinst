#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitstillimage();
	sleep 2;
	sendkey $cmd{"next"};
}

1;

#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitstillimage();
	sendkey $cmd{"next"};
}

1;

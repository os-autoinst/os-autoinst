#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitinststage("timezone");
	sendkey $cmd{"next"};
}

1;

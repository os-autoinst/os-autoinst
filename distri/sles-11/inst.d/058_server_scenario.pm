#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitidle;
	sendkey $cmd{"next"};
}

1;

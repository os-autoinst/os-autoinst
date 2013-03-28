#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitforneedle("inst-timezone");
	waitidle;
	sendkey $cmd{"next"};
}

1;

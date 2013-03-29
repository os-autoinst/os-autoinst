#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitforneedle("inst-timezone", 125) || die 'no timezone';
	sendkey $cmd{"next"};
}

1;

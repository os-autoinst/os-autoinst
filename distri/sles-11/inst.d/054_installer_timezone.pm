#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitforneedle("timezone");
	waitidle; sleep 9; # extra for NTP sync
	sendkey $cmd{"next"};
}

1;

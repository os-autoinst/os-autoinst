#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitinststage("timezone");
	waitidle; sleep 4; # extra for NTP sync
	sendkey $cmd{"next"};
}

1;

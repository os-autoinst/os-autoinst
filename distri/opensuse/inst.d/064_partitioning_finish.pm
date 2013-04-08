#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitstillimage();
	sendkey $cmd{"next"};
	waitforneedle("after-paritioning");
}

1;

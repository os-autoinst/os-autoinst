#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub is_applicable()
{
    my $self=shift;
    return $self->SUPER::is_applicable && !$ENV{UPGRADE};
}

sub run()
{
	waitstillimage();
	sendkey $cmd{"next"};
	waitforneedle("after-paritioning");
}

1;

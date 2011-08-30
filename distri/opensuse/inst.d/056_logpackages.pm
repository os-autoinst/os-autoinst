#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;

sub is_applicable()
{
        my $self=shift;
        $self->SUPER::is_applicable && !$ENV{LIVECD} && !$ENV{NICEVIDEO};
}

sub run()
{ my $self=shift;
	waitidle;
	sendkey "ctrl-alt-shift-x"; sleep 3;
	sendautotype "(cat .timestamp ; echo .packages.initrd: ; cat .packages.initrd)>/dev/$serialdev\n";
	sendautotype "(echo .packages.root: ; cat .packages.root)>/dev/$serialdev\n";
	sendautotype "ls -lR /update\n";
	$self->take_screenshot;
	waitidle;
	sendkey "ctrl-d"; sleep 3;
}

1;

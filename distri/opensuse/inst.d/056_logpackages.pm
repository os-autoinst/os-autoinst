#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
        my $self=shift;
        $self->SUPER::is_applicable && !$ENV{LIVECD} && !$ENV{NICEVIDEO} && !$ENV{UPGRADE};
}

sub run()
{ my $self=shift;
	waitforneedle("before-package-selection");
	#sendkey "ctrl-alt-shift-x"; sleep 3;
	sendkey "ctrl-alt-f2";
	waitforneedle("inst-console");
	sendautotype "(cat .timestamp ; echo .packages.initrd: ; cat .packages.initrd)>/dev/$serialdev\n";
	sendautotype "(echo .packages.root: ; cat .packages.root)>/dev/$serialdev\n";
	waitforneedle("inst-packagestyped", 150);
	sendautotype "ls -lR /update\n";
	$self->take_screenshot;
	waitidle;
	#sendkey "ctrl-d"; sleep 3;
        if (checkEnv('VIDEOMODE', 'text')) {
          sendkey "ctrl-alt-f1";
        } else {
	  sendkey "ctrl-alt-f7";
        }
	waitforneedle("inst-returned-to-yast", 15);

}

1;

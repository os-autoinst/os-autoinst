#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
	my $self=shift;
	return $self->SUPER::is_applicable && $ENV{UEFI} && $ENV{SECUREBOOT};
}

sub run()
{
    my $self=shift;

    # Make sure that we are in the installation overview with SB enabled
    waitforneedle("inst-overview-secureboot");

    $cmd{bootloader}="alt-b" if checkEnv('VIDEOMODE', "text");
    sendkey $cmd{change};        # Change
    sendkey $cmd{bootloader};    # Bootloader
    sleep 4;

    # Is secure boot enabled?
    waitforneedle("bootloader-secureboot-enabled", 5);
    sendkey $cmd{accept}; # Accept
    sleep 2;
    sendkey "alt-o"; # cOntinue
    waitidle;
}

1;

#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
        my $self=shift;
        $self->SUPER::is_applicable && $ENV{HW} && !$ENV{KEEPHDDS};
}

sub run()
{ my $self=shift;
	waitstillimage(30, 290);
	#sendkey "ctrl-alt-shift-x"; sleep 3;
	sendkey "ctrl-alt-f2"; sleep 3;
	my $disks = $bmwqemu::backend->{'hardware'}->{'disks'};
	for my $disk (@$disks) {
		sendautotype "wipefs -a $disk\n";
		sleep 1;
		sendautotype "dd if=/dev/zero of=$disk bs=1M count=1\n";
		sleep 2;
		sendautotype "blockdev --rereadpt $disk\n";
		sleep 4;
	}
	waitstillimage;
	$self->check_screen;
	#sendkey "ctrl-d"; sleep 3;
	my $instcon=($ENV{VIDEOMODE} eq "text")?1:7;
	sendkey "ctrl-alt-f$instcon"; sleep 3;
}

1;

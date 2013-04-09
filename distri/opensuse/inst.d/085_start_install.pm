#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub run()
{
	my $self=shift;
	# start install
	sendkey $cmd{install};
	waitforneedle("startinstall");
	# confirm
	$self->take_screenshot;
	sendkey $cmd{install};
        waitforneedle("inst-packageinstallationstarted");
	if(!$ENV{LIVECD} && !$ENV{NICEVIDEO}) {
		sleep 5;
		# view installation details
		sendkey $cmd{instdetails};
		if ($ENV{DVD} && !$ENV{NOIMAGES}) {
			if (checkEnv('DESKTOP', 'kde')) {
				waitforneedle('kde-imagesused', 100);
			} elsif (checkEnv('DESKTOP', 'gnome')) {
				waitforneedle('gnome-imagesused', 100);
			} else {
				waitforneedle('x11-imagesused', 100);
			}
		} 
	}
}

1;

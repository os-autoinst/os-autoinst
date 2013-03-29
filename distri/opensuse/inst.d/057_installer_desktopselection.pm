#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub is_applicable()
{
	my $self=shift;
	$self->SUPER::is_applicable && !$ENV{LIVECD};
}

sub run()
{
	my %desktopkeys=(kde=>"k", gnome=>"g", xfce=>"x", lxde=>"l", minimalx=>"m", "textmode"=>"i");
	waitforneedle("desktop-selection", 30);
	my $d=$ENV{DESKTOP};
	diag "selecting desktop=$d";
	$ENV{uc($d)}=1;
	my $key="alt-$desktopkeys{$d}";
	if($d eq "kde") {
		# KDE is default
	} elsif($d eq "gnome") {
		sendkey $key;
		waitforneedle("gnome-selected", 3);
	} else { # lower selection level
		sendkey "alt-o"; #TODO translate
		waitforneedle("other-desktop", 3);
		sendkey $key;
		sleep 3; # needles for else cases missing
	}
	sendkey $cmd{"next"};
	# ending at partition layout screen
}

1;

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
	waitinststage "desktopselection";
	my $d=$ENV{DESKTOP};
	diag "selecting desktop=$d";
	$ENV{uc($d)}=1;
	my $key="alt-$desktopkeys{$d}";
	if($d eq "kde") {
		# KDE is default
	} elsif($d eq "gnome") {
		sendkey $key;
	} else { # lower selection level
		sendkey "alt-o"; #TODO translate
		sleep 2;
		sendkey $key;
	}
	sleep 3; # to make selection visible
	sendkey $cmd{"next"};
	# ending at partition layout screen
}

1;

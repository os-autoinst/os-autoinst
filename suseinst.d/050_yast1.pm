#!/usr/bin/perl -w
use strict;
use base "basetest";
use bmwqemu;

sub run()
{
waitinststage("welcome", 490);

if($ENV{BETA} && !$ENV{LIVECD}) {
	# ack beta message
	sendkey "ret";
	#sendkey $cmd{acceptlicense};
}

# animated cursor wastes disk space, so it is moved to bottom right corner
mousemove_raw(0x7fff,0x7fff); 
mousemove_raw(0x7fff,0x7fff); # work around no reaction first time
# license+lang
sendkey $cmd{"next"};
if(!$ENV{LIVECD}) {
	# autoconf phase
	waitinststage "systemanalysis";
	# includes downloads, so waitidle is bad.
	waitgoodimage(25);
	# TODO waitstillimage(10)
	waitidle 29;
	# Installation Mode = new Installation
	if($ENV{UPGRADE}) {
		sendkey "alt-u";
	}
	sendkey $cmd{"next"};
}
if(!$ENV{UPGRADE}) {
# timezone
waitinststage("timezone");
sendkey $cmd{"next"};
if(!$ENV{LIVECD}) {
	my %desktopkeys=(kde=>"k", gnome=>"g", xfce=>"x", lxde=>"l", minimalx=>"m", "textmode"=>"i");
	waitinststage "desktopselection";
	$ENV{DESKTOP}||="kde";
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
		sendkey $key;
	}
	sleep 3; # to make selection visible
	sendkey $cmd{"next"};
}
# ending at partition layout screen
} else {
	# upgrade system select
	waitidle;
	sendkey $cmd{"next"};
	# repos
	waitidle;
	sendkey $cmd{"next"};
	sendkey "alt-u"; # Update if available
	waitidle 10;
	sendkey "alt-u"; # confirm
	sleep 20;
	sendkey "alt-d"; # details
	sleep 1200; # time for install
}
}

1;

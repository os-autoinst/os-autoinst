#!/usr/bin/perl -w

##################################################
# Written by:	Xudong Zhang <xdzhang@suse.com>
# Case:		1248944
##################################################

use strict;
use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	mouse_hide();
	x11_start_program("firefox");
	waitforneedle("test-firefox-1",5);
	if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # dont check for updated plugins
	if($ENV{DESKTOP}=~/xfce|lxde/i) {
		sendkey "ret"; # confirm default browser setting popup
		waitidle;
	}
	sendkey "alt-e"; sleep 2;
	checkneedle("firefox_menu-edit",3);
	sendkey "alt-v"; sleep 2;
	checkneedle("firefox_menu-view",3);
	for(1..2) {		#select the "Character Encoding" menu
		sendkey "up"; sleep 1;
	}
	for(1..2) {		#select "Auto-Detect" then "Chinese"
		sendkey "right"; sleep 1;
	}
	checkneedle("firefox_menu-submenu",3);
	for(1..3) {		#dismiss all opened menus one by one
		sendkey "esc"; sleep 1;
	}
	waitforneedle("test-firefox-1",3);

	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;

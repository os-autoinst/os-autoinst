#!/usr/bin/perl -w

##################################################
# Written by:	Xudong Zhang <xdzhang@suse.com>
# Case:		1248980
#Description:	Firefox Sidebar
#
#1.Click View from Firefox menu and click Sidebar.
#2.Select Bookmarks from Sidebar submenu.
#3.Click any bookmark
#4.Select History from Sidebar submenu.
#5.Click any history
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
	sendkey "ctrl-b"; sleep 1;		#open the bookmark sidebar
	sendkey "tab"; sleep 1;
	sendkey "ret"; sleep 1;			#unfold the "Bookmarks Toolbar"
	sendkey "down"; sleep 1;		#down twice to select the "openSUSE" folder
	sendkey "down"; sleep 1;
	sendkey "ret"; sleep 1;			#open the "openSUSE" folder
	sendkey "down"; sleep 1;		#down twice to select the "openSUSE Documentation"	
	sendkey "down"; sleep 1;
	sendkey "ret"; sleep 5;			#open the selected bookmark
	checkneedle("firefox_sidebar-bookmark",5);
	sendkey "ctrl-b"; sleep 1;		#close the "Bookmark sidebar"
#begin to test the history sidebar
	sendkey "ctrl-h"; sleep 1;
	sendkey "tab"; sleep 1;			#twice tab to select the "Today"
	sendkey "tab"; sleep 1;
	sendkey "ret"; sleep 1;			#unfold the "Today"
	sendkey "down"; sleep 1;		#select the first history
	sendkey "down"; sleep 1;
	sendkey "ret"; sleep 5;
	checkneedle("firefox_sidebar-history",5);
	sendkey "ctrl-h"; sleep 1;

#recover all the changes
	sendkey "ctrl-b"; sleep 1;
	sendkey "tab"; sleep 1;
	sendkey "down"; sleep 1;		#down twice to select the "openSUSE" folder
	sendkey "down"; sleep 1;
	sendkey "ret"; sleep 1;			#close the "openSUSE" folder
	sendkey "up"; sleep 1;
	sendkey "up"; sleep 1;
	sendkey "ret"; sleep 1;			#close the "Bookmark Toolbar"
	sendkey "ctrl-b"; sleep 1;		#close the bookmark sidebar

	sendkey "ctrl-h"; sleep 1;
	sendkey "tab"; sleep 1;			#twice tab to select the "Today"
	sendkey "tab"; sleep 1;
	sendkey "ret"; sleep 1;			#close the "Today"
	sendkey "ctrl-h"; sleep 1;

	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;

#!/usr/bin/perl -w

##################################################
# Written by:	Xudong Zhang <xdzhang@suse.com>
# Case:		1248975
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

	my @sites=('www.baidu.com', 'www.novell.com', 'www.google.com');

	for my $site (@sites) {
		sendkey "ctrl-l"; sleep 1;
		sendautotype $site."\n"; sleep 5;
		$site=~s{\.com}{};
		$site=~s{.*\.}{};
		checkneedle("firefox_page-".$site,5);
	}
	
	sendkey "alt-left"; sleep 2;
	sendkey "alt-left"; sleep 3;
	checkneedle("firefox_page-baidu",5);
	sendkey "alt-right"; sleep 3;
	checkneedle("firefox_page-novell",5);
	sendkey "f5"; sleep 3;
	checkneedle("firefox_page-novell",5);
	
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;

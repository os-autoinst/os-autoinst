#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248971
# Description:    open new window and open link in new window
##################################################

use strict;
use base "basetest";
use bmwqemu;

sub run()
{
    my $self=shift;
    mouse_hide();
    x11_start_program("firefox");
    waitforneedle("start-firefox",5);
    if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # dont check for updated plugins
    if($ENV{DESKTOP}=~/xfce|lxde/i) {
        sendkey "ret"; # confirm default browser setting popup
        waitidle;
    }
    
    sendkey "ctrl-n"; sleep 5;
    checkneedle("start-firefox",5);
    sendkey "ctrl-w"; sleep 1;
    
    sendkey "shift-tab"; sleep 1;
    sendkey "shift-ret"; sleep 5;
    checkneedle("firefox_page-novell",5);
    sendkey "ctrl-w"; sleep 1;
        
    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;


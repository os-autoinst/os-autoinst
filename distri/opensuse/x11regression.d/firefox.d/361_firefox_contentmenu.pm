#!/usr/bin/perl -w

##################################################
# Written by:   Xudong Zhang <xdzhang@suse.com>
# Case:     1248972
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

    sendkey "shift-f10"; sleep 1;
    checkneedle("firefox_contentmenu",5);
    sendkey "down"; sleep 1;
    sendkey "down"; sleep 1;
    checkneedle("firefox_contentmenu-arrow",5);
    sendkey "i"; sleep 2;
    checkneedle("firefox_pageinfo",5);      #the page info of opensuse.org
    sendkey "alt-f4"; sleep 1;          #close the page info window
    sendkey "shift-f10"; sleep 1;
    sendkey "esc"; sleep 1;             #show that esc key can dismiss the menu 


    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;


#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248977
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


    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    sendkey "alt-p"; sleep 1;
    sendautotype "www.google.com"; sleep 2;
    checkneedle("firefox_pref-general-homepage",5);
    sendkey "ret"; sleep 1;
    sendkey "alt-home"; sleep 5;
    checkneedle("firefox_page-google",5);
#exit and relaunch the browser 
    sendkey "alt-f4"; sleep 2;
    x11_start_program("firefox");
    checkneedle("firefox_page-google",5);
#recover all the changes, home page
    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    sendkey "alt-r"; sleep 1;        #choose "Restore to Default"
    sendkey "esc"; sleep 1;

    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;

#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248978
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

    sendkey "ctrl-k"; sleep 1;
    sendkey "ret"; sleep 5;
    checkneedle("firefox_page-google",5);        #check point 1
    sendkey "ctrl-k"; sleep 1;
    sendautotype "opensuse"."\n"; sleep 5;
    checkneedle("firefox_search-opensuse",5);    #check point 2
    sendkey "ctrl-k"; sleep 1;
    sendkey "f4"; sleep 1;
    sendkey "y"; sleep 1;                #select the yahoo as search engine
    sendkey "ret"; sleep 5;
    checkneedle("firefox_yahoo-search",5);        #check point 4

#recover the changes, change search engine to google
    sendkey "ctrl-k"; sleep 1;
    sendkey "f4"; sleep 1;
    sendkey "g"; sleep 1;

    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;


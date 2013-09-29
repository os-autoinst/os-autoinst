#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248985
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

    sendkey "ctrl-l"; sleep 1;
    sendautotype "https://www.google.com"."\n"; sleep 6;
    checkneedle("firefox_https-google",3);

    sendkey "ctrl-l"; sleep 1;
    sendautotype "http://147.2.207.207/repo"."\n"; sleep 3;
    checkneedle("firefox_http207",3);

    sendkey "ctrl-l"; sleep 1;
    sendautotype "https://147.2.207.207/repo"."\n"; sleep 3;
    checkneedle("firefox_https-risk",3);
    sendkey "shift-tab"; sleep 1;        #select "I Understand..."
    sendkey "ret"; sleep 1;            #open the "I Understand..."
    sendkey "tab"; sleep 1;            #select the "Add Exception"
    sendkey "ret"; sleep 1;            #click "Add Exception"
    checkneedle("firefox_addexcept",3);
    sendkey "alt-c"; sleep 1;
    checkneedle("firefox_https-207",3);        

    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;

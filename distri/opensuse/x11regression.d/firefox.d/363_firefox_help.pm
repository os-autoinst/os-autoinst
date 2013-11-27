#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248964
# Description:    Test firefox help
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

    sendkey "alt-h"; sleep 1;
    sendkey "h"; sleep 6;
    checkneedle("firefox_help-help",8);
    sendkey "ctrl-w"; sleep 1;        #close the firefox help tab
    sendkey "alt-h"; sleep 1;
    sendkey "t"; sleep 1;
    checkneedle("firefox_help-trouble",3);
    sendkey "ctrl-w"; sleep 1;        #close the firefox troubleshooting tab
    sendkey "alt-h"; sleep 1;
    sendkey "s"; sleep 6;
    checkneedle("firefox_help-feedback",8);
    sendkey "ctrl-w"; sleep 1;        #close the firefox submit feedback tab
#test firefox--report web forgery
    sendkey "alt-h"; sleep 1;
    sendkey "f"; sleep 6;
    checkneedle("firefox_help-forgery",5);    #need to close tab cause if open in current tab
#test firefox--about firefox
    sendkey "alt-h"; sleep 1;
    sendkey "a"; sleep 1;
    checkneedle("firefox_help-about",5);
    sendkey "alt-f4"; sleep 1;        #close the firefox about dialog
#test firefox help--restart with addons disable
    sendkey "alt-h"; sleep 1;
    sendkey "r"; sleep 2;
    checkneedle("firefox_restart-addons-disable",5);
    sendkey "ret"; sleep 3;
    checkneedle("firefox_safemode",3);
    sendkey "ret"; sleep 4;
    checkneedle("firefox_help-forgery",5);    #will open last closed website
    sendkey "ctrl-shift-a"; sleep 3;
    sendkey "tab"; sleep 1;
    sendkey "tab"; sleep 1;            #switch to extension column of add-ons
    sendkey "down"; sleep 1;
    checkneedle("firefox_addons-safemode",5);
#recover all changes--switch addons page to default column
    sendkey "up"; sleep 1;
    sendkey "ctrl-w"; sleep 1;        #close the firefox addons tab


    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;


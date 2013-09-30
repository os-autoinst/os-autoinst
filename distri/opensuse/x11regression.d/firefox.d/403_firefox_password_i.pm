#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248984
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

    sendkey "ctrl-l"; sleep 2;
#login mail.google.com
    sendautotype "mail.google.com\n"; sleep 4;
    checkneedle("firefox_page-gmail1",5);
    sendautotype "nooops6"; sleep 1;
    sendkey "tab"; sleep 1;
    sendautotype "opensuse\n"; sleep 6;
    checkneedle("firefox_page-gmail2",5);
    sendkey "alt-r"; sleep 1;        #remember password
    sendkey "r"; sleep 1;
#clear recent history otherwise gmail will login automatically
    sendkey "ctrl-shift-delete"; sleep 2;
    sendkey "shift-tab"; sleep 1;        #select clear now
    sendkey "ret"; sleep 1;
#login mail.google.com again to check the password
    sendkey "ctrl-l"; sleep 2;
    sendautotype "mail.google.com\n"; sleep 4;
    checkneedle("firefox_page-gmail3",3);

#recover all the changes
    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    for(1..3) {            #select the "Security" tab of Preference
        sendkey "left"; sleep 1;
    }
    sendkey "alt-p"; sleep 1;
    sendkey "alt-a"; sleep 1;
    sendkey "y"; sleep 1;
    sendkey "alt-c"; sleep 1;
    sendkey "esc"; sleep 1;            #close the Preference
    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    for(1..3) {                #switch the tab from "Security" to "General" 
        sendkey "right"; sleep 1;
    }
    sendkey "esc"; sleep 1;
        
    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;

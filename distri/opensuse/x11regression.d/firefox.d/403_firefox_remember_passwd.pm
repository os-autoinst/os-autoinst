#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248981
#Description:    Firefox Sidebar
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
    waitforneedle("start-firefox",5);
    if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # dont check for updated plugins
    if($ENV{DESKTOP}=~/xfce|lxde/i) {
        sendkey "ret"; # confirm default browser setting popup
        waitidle;
    }
    
    my $master_passwd="123456";
    my $test_site="calendar.google.com";
    my $gmailuser="nooops6";
    my $gmailpasswd="opensuse";

    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    for(1..3) {            #select the "Security" tab of Preference
        sendkey "left"; sleep 1;
    }
    sendkey "alt-u"; sleep 1;    #choose "Use a master password"
    sendautotype $master_passwd; sleep 1;
    sendkey "tab"; sleep 1;        #re-enter password
    sendautotype $master_passwd."\n"; sleep 1;
    sendkey "ret"; sleep 1;        #"Password Change Succeeded" diag
    sendkey "esc"; sleep 1;
    
    sendkey "ctrl-l"; sleep 1;
    sendautotype $test_site."\n"; sleep 5;
    checkneedle("firefox_page-calendar",5);
    sendautotype $gmailuser; sleep 1;
    sendkey "tab"; sleep 1;
    sendautotype $gmailpasswd."\n"; sleep 5;
    checkneedle("firefox_remember-password",5);
    sendkey "alt-r"; sleep 1;        #remember password
    sendkey "r"; sleep 1;
    sendautotype $master_passwd."\n"; sleep 1;
    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    sendkey "alt-p"; sleep 1;        #open the "Saved Passwords" diag
    checkneedle("firefox_saved-passowrds",5);    #check if the passwd is saved
    sendkey "alt-c"; sleep 1;        #close the dialog
    sendkey "esc"; sleep 1;
    sendkey "alt-f4"; sleep 2;        #quit firefox and then re-launch
    sendkey "ret"; sleep 2; # confirm "save&quit"
#re-open firefox and login the calendar
    x11_start_program("firefox");
#clear recent history otherwise calendar will login automatically
    sendkey "ctrl-shift-delete"; sleep 1;
    sendkey "shift-tab"; sleep 1;        #select clear now
    sendkey "ret"; sleep 1;
#login calendar.google.com again to check the password
    sendkey "ctrl-l"; sleep 2;
    sendautotype $test_site."\n"; sleep 5;
    checkneedle("firefox_passwd-required",5);
    sendautotype $master_passwd."\n"; sleep 1;
    checkneedle("firefox_page-calendar-passwd",3);
    
#recover all the changes
    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    sendkey "alt-p"; sleep 1;        #open the "Saved Passwords" diag
    sendkey "alt-a"; sleep 1;        #remove all the saved passwords
    sendkey "y"; sleep 1;            #confirm the removing
    sendkey "alt-c"; sleep 1;        #close the "Saved..." dialog
    sendkey "alt-u"; sleep 2;        #disable the master password
    sendautotype $master_passwd."\n"; sleep 1;
    sendkey "ret"; sleep 1;            #answer to the popup window
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

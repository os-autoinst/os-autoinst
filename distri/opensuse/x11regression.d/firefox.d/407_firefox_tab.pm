#!/usr/bin/perl -w

###########################################################
# Test Case:	1248950
# Case Summary: Firefox: Test firefox tabbed brower windows
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# firefox-open
# firefox_pre-general
# test-firefox_tab-1, test-firefox_tab-2, test-firefox_tab-3
# test-firefox_tab-4, test-firefox_tab-5

# NOTE: Some actions in this case can not be implemented.
# For example, click and drag. So they are not included.

use strict;
use base "basetest";
use bmwqemu;

sub run()
{
    my $self=shift;
    mouse_hide();

    # Launch firefox
    x11_start_program("firefox");
    waitforneedle("start-firefox",5);
    if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # Don't check for updated plugins
    if($ENV{DESKTOP}=~/xfce|lxde/i) {
        sendkey "ret"; # Confirm default browser setting popup
        waitidle;
    }
    sendkey "alt-f10"; sleep 1;     # Maximize

    # Opening a new Tabbed Browser.
    sendkey "alt-f"; sleep 1;
    sendkey "ret"; sleep 1;         # Open a new tab by menu
    sendkey "ctrl-t"; # Open a new tab by hotkey
    sleep 2;
    checkneedle("test-firefox_tab-1",5); sleep 2;
    sendkey "ctrl-w"; sendkey "ctrl-w"; # Restore to one tab (Home Page)

    # Confirm that the various menu items pertaining to the Tabbed Browser exist
    # Confirm the page title and url.
    sendkey "apostrophe"; sleep 1;
    sendautotype "news"; sendkey "esc"; sleep 1; # Find News link
    sendkey "menu"; sleep 1; # Use keyboard to simulate right click the link
    sendkey "down"; sendkey "ret"; # "Open link in the New Tab"
    sleep 6;
    sendkey "alt-2"; sleep 5;       # Switch to the new opened tab
    checkneedle("test-firefox_tab-2",5);
    sendkey "ctrl-w"; sleep 1;       # Restore to one tab (Home Page)

    # Test secure sites
    sendkey "ctrl-t"; sleep 1;
    sendkey "alt-d"; sleep 1;
    sendautotype "http://mozilla.org/\n"; sleep 10; # A non-secure site (http) 
    checkneedle("test-firefox_tab-3",5);

    sendkey "ctrl-t"; sleep 1;
    sendkey "alt-d"; sleep 1;
    sendautotype "https://digitalid.verisign.com/\n"; sleep 10; # A secure site (https) 
    checkneedle("test-firefox_tab-4",5);

    sendkey "ctrl-w"; sendkey "ctrl-w"; # Restore to one tab (Home Page)

    # Confirm default settings
    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;               # Open Preferences
	checkneedle("firefox_pre-general",5);
    sleep 5;
    sendkey "right"; sleep 2; # Switch to the "Tabs" tab
    checkneedle("test-firefox_tab-5",5); sleep 2;

    sendkey "left"; sleep 1;
    sendkey "esc"; sleep 1;     # Restore

    # Restore and close firefox
    sendkey "alt-f4"; sleep 1; # Exit firefox
	sendkey "ret"; # Confirm "save&quit"
    x11_start_program("rm -rf .mozilla"); # Clear profile directory
    sleep 2;
     
}   

1;

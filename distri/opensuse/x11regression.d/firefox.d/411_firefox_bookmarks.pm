#!/usr/bin/perl -w

###########################################################
# Test Case:	1248956
# Case Summary: Firefox: Test bookmarks in firefox
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# firefox-open
# test-firefox_bookmarks-open, test-firefox_bookmarks-add01, test-firefox_bookmarks-add02
# test-firefox_bookmarks-folder, test-firefox_bookmarks-new, test-firefox_bookmarks-surf
# test-firefox_bookmarks-delete
# test-firefox_bookmarks-edit01, test-firefox_bookmarks-edit02, test-firefox_bookmarks-edit03

use strict;
use base "basetest";
use bmwqemu;

sub run()
{
    my $self=shift;
    mouse_hide();

    # Launch firefox
    x11_start_program("firefox");
    waitforneedle("firefox-open",5);
    if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # Don't check for updated plugins
    if($ENV{DESKTOP}=~/xfce|lxde/i) {
        sendkey "ret"; # Confirm default browser setting popup
        waitidle;
    }
    sendkey "alt-f10"; sleep 1;     # Maximize

    #View bookmarks
    sendkey "ctrl-b"; sleep 1;
    sendkey "alt-s"; sleep 1; #Search (To avoid using "Tab" as much as possible)
    sendautotype "Getting"; sleep 3;
    sendkey "tab"; sendkey "down"; #Focus on the "Getting Start" bookmark
    sendkey "ret"; sleep 10; #Open the bookmark
    checkneedle("test-firefox_bookmarks-open",5);
    sendkey "ctrl-b"; sleep 2; #Close bookmarks sidebar

    #Add bookmarks
    sendkey "f6";
    sendautotype "www.google.com\n"; sleep 3;
    sendkey "ctrl-d"; sleep 1;#Add bookmark
    checkneedle("test-firefox_bookmarks-add01",5); 
    sendkey "ret";
    sendkey "ctrl-b"; sleep 1;#Open sidebar
    sendkey "tab"; sendkey "down";
    sendkey "ret"; sleep 2; #Unfold Bookmarks Menu
    checkneedle("test-firefox_bookmarks-add02",5);
    sendkey "ctrl-b"; sleep 2; #Close bookmarks sidebar

    #New Folder
    sendkey "ctrl-b"; sleep 1;#Open sidebar
    sendkey "tab";
    sendkey "right"; #Unfold Bookmarks Toolbar
    sendkey "down"; sendkey "up"; sleep 1;#Make focus
    sendkey "menu"; sleep 1; #Right click menu
    sendkey "f"; sleep 1; #New Folder
    sendkey "alt-n"; sleep 1;
    sendkey "ctrl-a";
    sendautotype "suse-test\n"; sleep 1; #Input folder name
    checkneedle("test-firefox_bookmarks-folder",5);

    #New bookmarks
    sendkey "menu"; sleep 1;#Right click menu
    sendkey "b"; sleep 1; # New Bookmark
    sendkey "alt-n";
    sendkey "ctrl-a"; #Name
    sendautotype "Free Software Foundation";
    sendkey "alt-l"; #Location
    sendautotype "http://www.fsf.org/\n"; sleep 1; #Add
    sendkey "right"; sleep 1; #Unfolder
    checkneedle("test-firefox_bookmarks-new",5);

    #Surf bookmarks
    sendkey "down"; #Focus on new created bookmark
    sendkey "ret"; sleep 5;
    checkneedle("test-firefox_bookmarks-surf",5);

    #Delete bookmarks
    sendkey "alt-s"; #Search field
    sendautotype "Free\n"; sleep 1;
    sendkey "tab"; sendkey "down"; #Focus on the bookmark to be deleted
    sendkey "menu"; sleep 1;
    sendkey "d"; sleep 1; #Delete
    sendkey "alt-s"; sendkey "delete"; sleep 1; #Cancel searched
    checkneedle("test-firefox_bookmarks-delete",5);
 
    #Edit bookmark proerties
    sendkey "ctrl-shift-o"; sleep 2;
    checkneedle("test-firefox_bookmarks-edit01",5);
    sendkey "down"; sendkey "ret"; #Bookmarks Menu
    foreach (1..5) {sendkey "down";} #Move to Google bookmark we created at the beginning
    sleep 2;
    sendkey "alt-n"; #Name
    sendautotype "Google Maps"; sleep 1;
    sendkey "alt-l"; #Location
    sendautotype "https://maps.google.com"; sleep 1;
    sendkey "alt-f4"; sleep 1; #Close bookmarks window
    checkneedle("test-firefox_bookmarks-edit02",5); sleep 1;
    sendkey "alt-s";
    sendautotype "Maps"; sleep 1;
    sendkey "tab"; sendkey "down"; sleep 1;#Focus on "Google Maps" bookmark
    sendkey "ret"; sleep 5; #Load the bookmark
    checkneedle("test-firefox_bookmarks-edit03",5); sleep 1;
    
    # Restore and close firefox
    x11_start_program("killall -9 firefox"); # Exit firefox
    x11_start_program("rm -rf .mozilla"); # Clear profile directory
    sleep 2;
}   

1;

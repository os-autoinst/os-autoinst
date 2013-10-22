#!/usr/bin/perl -w

###########################################################
# Test Case:	1248953
# Case Summary: Firefox - Java plugin
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# firefox-open
# test-firefox_java-1, test-firefox_java-2, test-firefox_java-3
# test-firefox_java-java_warning

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


    # Open Add-ons Manager
    sendkey "ctrl-shift-a"; sleep 2;

    # Open "Email link" to launch default email client (evolution)
    sendkey "ctrl-f"; sleep 1; #"Search all add-ons"
    sendautotype "icedTea\n"; sleep 2;

    #Switch to "My Add-ons"
    foreach (1..5) {
        sendkey "tab";
    }
    sendkey "left"; sleep 2;

    waitforneedle("test-firefox_java-1",5);

    #Focus to "Always Activate"
    sendkey "tab";
    sendkey "down";
    sendkey "tab";
    sendkey "tab";
    sendkey "down"; #Switch to "Never Active"
    sleep 2;

    #Test java plugin on website javatester.org
    sendkey "ctrl-t"; sleep 1;
    sendautotype "javatester.org/version.html\n"; sleep 5;
    checkneedle("test-firefox_java-2",5);

    #Close tab, return to Add-ons Manager
    sendkey "ctrl-w"; sleep 2;
    sendkey "down"; sleep 1; #Switch back to "Always Activate" 

    #Test java plugin again
    sendkey "ctrl-t"; sleep 2;
    sendautotype "javatester.org/version.html\n"; sleep 4;
    checkneedle("test-firefox_java-java_warning",5); #Java - unsigned application warning
    sendkey "tab"; #Proceed
    sendkey "ret"; sleep 3;
    checkneedle("test-firefox_java-3",5);

    # Restore and close firefox
    x11_start_program("killall -9 firefox"); # Exit firefox
    x11_start_program("rm -rf .mozilla"); # Clear profile directory
    sleep 2;
     
}   

1;

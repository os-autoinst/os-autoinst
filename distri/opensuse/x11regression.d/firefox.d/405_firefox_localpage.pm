#!/usr/bin/perl -w

###########################################################
# Test Case:	1248948
# Case Summary: Firefox: Open static html page from local directory in firefox
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# firefox-open
# test-firefox-openfile-1
# test-firefox_lcoalpage-1 

use strict;
use base "basetest";
use bmwqemu;

sub run()
{
    my $self=shift;
    mouse_hide();

    # Download a static html page in the local machine.
    x11_start_program("wget -p --convert-links http://www.gnu.org\n");
    sleep 5;

    # Launch firefox
    x11_start_program("firefox");
    waitforneedle("start-firefox",5);
    if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # Don't check for updated plugins
    if($ENV{DESKTOP}=~/xfce|lxde/i) {
        sendkey "ret"; # Confirm default browser setting popup
        waitidle;
    }

    sendkey "alt-f10"; # Maximize

    # Open static html page
    sendkey "ctrl-o"; sleep 1; #"Open File" window
    checkneedle("test-firefox-openfile-1",5); 

    # Find index.html file to open
    sendkey "left";
    sendkey "down";
    sendkey "right"; sleep 1;
    sendautotype "www.gnu\n"; # find the directory www.gnu.org and enter
    sleep 2;
    sendautotype "index\n"; # Find file index.html and open it
    sleep 5;
    checkneedle("test-firefox_lcoalpage-1",5);
    
    # Restore and close
    sendkey "alt-f4"; sleep 1; # Exit firefox
    sendkey "ret"; # Confirm "save&quit"
    x11_start_program("rm -rf .mozilla\n");  # Clear profile directory
    x11_start_program("rm -rf www.gnu.org\n"); # Remove www.gnu.org directory
    sleep 2;

}

1;

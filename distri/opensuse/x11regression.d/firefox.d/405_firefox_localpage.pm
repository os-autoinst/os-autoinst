#!/usr/bin/perl -w

###########################################################
# Test Case:	1248948
# Case Summary: Firefox: Open static html page from local directory in firefox
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# test-firefox-1
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
    waitforneedle("test-firefox-1",5);
    if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # Don't check for updated plugins
    if($ENV{DESKTOP}=~/xfce|lxde/i) {
        sendkey "ret"; # Confirm default browser setting popup
        waitidle;
    }

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
    sendkey "ctrl-w"; # Close the only tab (exit)
    sendkey "ret"; sleep 2; # confirm "save&quit"
    x11_start_program("xterm"); sleep 2;
    sendautotype "rm -rf ~/www.gnu.org\n"; sleep 1; # Remove www.gnu.org directory
    sendautotype "rm -f ~/.mozilla/firefox/*.default/prefs.js\n"; sleep 1; # Remove prefs.js to avoid browser remember default folder used by "Open File" window
    sendkey "ctrl-d"; # Exit xterm

}

1;

#!/usr/bin/perl -w

###########################################################
# Test Case:	1248949, 1248951
# Case Summary: Firefox: MHTML load IE 7 files from local disk in Firefox
# Case Summary: Firefox: MHTML load IE 6 files from web server in Firefox
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# test-firefox-1
# test-firefox-openfile-1
# test-firefox_mhtml-1, test-firefox_mhtml-2

use strict;
use base "basetest";
use bmwqemu;

sub run()
{
    my $self=shift;
    mouse_hide();

    # Backup firefox profiles
    x11_start_program("cp -r .mozilla mozilla-backup");

    # Download a mhtml file to the local machine.
    x11_start_program("wget http://www.fileformat.info/format/mime-html/sample/9c96b3d179f84b98b35d4c8c2ec13e04/download -O google.mht");
    sleep 6;

    # Launch firefox
    x11_start_program("firefox");
    waitforneedle("test-firefox-1",5);
    if($ENV{UPGRADE}) { sendkey("alt-d");waitidle; } # Don't check for updated plugins
    if($ENV{DESKTOP}=~/xfce|lxde/i) {
        sendkey "ret"; # Confirm default browser setting popup
        waitidle;
    }

    # Install UnMHT extension
    sendkey "ctrl-shift-a"; sleep 5; # Add-ons Manager
    sendkey "alt-d"; sleep 2;
    sendautotype "https://addons.mozilla.org/firefox/downloads/latest/8051/addon-8051-latest.xpi\n"; sleep 15; # Install the extension 
    checkneedle("test-firefox_mhtml-1",5);
    sendkey "ret"; sleep 2;
    sendkey "ctrl-w";

    # Open mhtml file
    sendkey "ctrl-o"; sleep 1; #"Open File" window
    checkneedle("test-firefox-openfile-1",5); 

    # Find .mht file to open
    sendkey "left";
    sendkey "down";
    sendkey "right"; sleep 1;
    sendautotype "google\n"; # find the directory www.gnu.org and enter
    sleep 5;
    sendkey "tab";
    checkneedle("test-firefox_mhtml-2",5); sleep 2;

    # Open remote mhtml address
    sendkey "alt-d"; sleep 1;
    sendautotype "http://www.fileformat.info/format/mime-html/sample/9c96b3d179f84b98b35d4c8c2ec13e04/google.mht\n";
    sleep 10;
    checkneedle("test-firefox_mthml-3",5); sleep 2;
    
    # Restore and close

    ###############################################################
    # There are too many trouble to restore the original status.
    # (See the codes below, they have been commented out)
    # So we simply remove the profiles (~/.mozill/) and copy back
    # the original ones.
    ###############################################################

    # Remove the UnMHT extension
    # sendkey "ctrl-shift-a"; sleep 5; # "Add-ons" Manager
    # sendkey "ctrl-f"; sleep 1;
    # sendautotype "unmht\n"; sleep 2; # Search
    # for (1...5){
    #    sendkey "tab";sleep 1;
    # }
    # sendkey "left"; # Select "My Add-ons"
    # sendkey "tab"; sendkey "down";
    # for (1...4){
    #     sendkey "tab"; sleep 1;
    # }
    # sendkey "spc"; sleep 1;# Remove
    # sendkey "ctrl-f"; sleep 1;
    # for (1...5){
    #     sendkey "tab";sleep 1;
    # }
    # sendkey "right";
    # sendkey "ctrl-w"; # Close "Add-ons" Manager
    # 

    # sendkey "ctrl-w"; # Close the only tab (exit)
    # sendkey "ret"; sleep 2; # confirm "save&quit"
    # x11_start_program("xterm"); sleep 2;
    # sendautotype "rm -f ~/.mozilla/firefox/*.default/prefs.js\n"; sleep 1; # Remove prefs.js to avoid browser remember default folder used by "Open File" window
    # sendkey "ctrl-d"; # Exit xterm

    sendkey "ctrl-w"; # Close the only tab (exit)
    sendkey "ret"; sleep 2; # confirm "save&quit"

    x11_start_program("rm -rf .mozilla;mv mozilla-backup .mozilla"); # Restore original profiles
    x11_start_program("rm -rf google.mht\n"); sleep 1; # Remove .mht file
     
}   

1;

#!/usr/bin/perl -w

###########################################################
# Test Case:	1248955
# Case Summary: Firefox - Autofill
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# firefox-open
# test-firefox_autocomplete-1
# firefox_autocomplete-testpage, firefox_autocomplete-testpage_filled

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

    # Open testing webpage for autocomplete
    sendkey "f6";
    sendautotype "debugtheweb.com/test/passwordautocomplete.asp\n"; sleep 4;
    checkneedle("firefox_autocomplete-testpage",5);

    sendkey "tab"; sendkey "tab"; sleep 1; # Focus to Username input field
    sendautotype "suse-test";
    sendkey "tab"; sleep 1; # Password field
    sendautotype "testpassword";
    sendkey "tab"; # "Standard Submit" button
    sendkey "ret";
    sleep 3;

    checkneedle("fierfox_autocomplete-1",5);

    sendkey "alt-r"; sendkey "alt-r"; sendkey "ret"; #Remember Password
    sleep 5;
    sendkey "alt-f4"; sleep 1;#Close browser
    sendkey "ret"; sleep 2; # confirm "save&quit"

    #Launch firefox again
    x11_start_program("firefox"); sleep 5;
    sendkey "f6";
    sendautotype "debugtheweb.com/test/passwordautocomplete.asp\n"; sleep 4;
    checkneedle("firefox_autocomplete-testpage_filled",5);

    # Restore and close firefox
    x11_start_program("killall -9 firefox"); # Exit firefox
    x11_start_program("rm -rf .mozilla"); # Clear profile directory
    sleep 2;
}

1;

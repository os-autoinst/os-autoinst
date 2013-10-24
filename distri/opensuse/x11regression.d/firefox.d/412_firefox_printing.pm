#!/usr/bin/perl -w

###########################################################
# Test Case:	1248954
# Case Summary: Firefox: Test printing in firefox
# Written by:	wnereiz@github
###########################################################

# Needle Tags:
# firefox-open
# test-firefox_printing-{name}

# CAUTION:
# Some of the tests in this case are not included in the script, 
# because the web pages are always changed.
# Check following table for detail:
#
# Frame Test                        *
# Formats Test                      *
# Test Page                         N (Mozilla front page is always changing, we should find a new test page)
# Alignment Test                    *
# Indentation Test                  *
# Settings Test                     *
# HTML Test                         *
# Page Source Test                  N (Website always changed, we should find a new test page)
# CSS Tests                         N (Some links are not available, we should find a new test page)
# Mozillazine poll result page      N (Link is not available anymore, we should find a new test page)
# Large Pages Test                  N (cnn.com page always changing, we should find a new test page)
# XML Test                          N (Link is not available anymore, we should find a new test page)
# Web Sites Test                    N (Top web pages are always changing, we should find a new test page)
# HTML 4.0 TESTS                    N (www.w3.org pages are always changing, we should find a new test page)
# Images Test                       > Test separately in 413_firefox_printing_images.pm
# Lists Test                        *
# Tables Test                       *
# Characters Test                   *
# Paragraph Test                    *
# Print Preview Test                N (Website always changed, will test separately)
# Page Setup (mac only)             N (Mac only)
# Offline Test                      *
# Header Test                       * (Together with Offline Test)
# Print Range Test                  * (Together with Offline Test)
#
# Note: Mozilla printing test main page:
#       http://www-archive.mozilla.org/quality/browser/front-end/testcases/printing/

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

    # Define the pages to be tested (last part of urls)

    my @test_pages=(
            { name => 'horizframetest', page_down => '0', remark => '' },
            { name => 'vertframetest',  page_down => '0', remark => '' },
            { name => 'formats',        page_down => '1', remark => '' },
            { name => 'print_alignment',page_down => '1', remark => '' },
            { name => 'indentation',    page_down => '0', remark => '' },
            { name => 'settings',       page_down => '0', remark => 'landscape' },
            { name => 'widgets',        page_down => '2', remark => '' },
            { name => 'list',           page_down => '1', remark => '' },
            { name => 'tables1',        page_down => '1', remark => '' },
            { name => 'bold',           page_down => '1', remark => '' },
            { name => 'paragraph1',     page_down => '1', remark => '' },
            { name => 'offlineprint',   page_down => '2', remark => 'offline' }
            # The purpose of setting page_down to 2 here is to test print range. Only two pages will be printed.
            # To make sure the last page is page 2, we just simply check whether page 3 is shown as blank in evince.

        );

    # Define base url
    my $base_url= "www-archive.mozilla.org/quality/browser/front-end/testcases/printing/";


    foreach (@test_pages) {

        sendkey "alt-d"; sleep 1;
        if ($_->{remark} eq "offline") {
            sendautotype "developer.mozilla.org/en/docs/Windows_Build_Prerequisites\n"; # Do not use base url here 
            sleep 15;
            # Set offline
            sendkey "alt-f"; sleep 1;
            sendkey "k";
            
        }else {
            sendautotype $base_url.$_->{name}.".html\n"; # Full URL
        }

        sleep 10;
        sendkey "ctrl-p"; sleep 1; # Open "Print" window

        # Test landscape printing
        if ($_->{remark} eq "landscape") {
            sendkey "ctrl-pgdn"; sleep 1; # Switch to "Page setup" tab
            sendkey "alt-i";
            sendkey "down"; sleep 1; # Set to landscape
            sendkey "ctrl-pgup"; sleep 1; # Switch back to "General" tab
        }else {
            sendkey "tab"; # Choose "Print to File"
        }

        # Set file name
        sendkey "alt-n"; sleep 1;
        sendautotype $_->{name}.".pdf";

        # We test the print range at the same time when in offline mode
        if ($_->{remark} eq "offline") {
            sendkey "alt-e"; sleep 1;
            sendautotype "1-2"; sleep 1;
        }

        # Print
        sendkey "alt-p"; sleep 5;

        # Some restore work for each test
        if ($_->{remark} eq "landscape") { # Restore the orientation to portrait
            sendkey "alt-f"; sleep 1;
            sendkey "u"; sleep 1;
            sendkey "alt-o"; sleep 1;
            sendkey "alt-a"; sleep 1;
        }elsif ($_->{remark} eq "offline") { # Disable offline mode
            sendkey "alt-f"; sleep 1;
            sendkey "k";
        }

        # Open printed pdf file by evince
        x11_start_program("evince ".$_->{name}.".pdf"); sleep 3;
        sendkey "f5"; sleep 2; # Slide mode

        # Use Pagedown to view every page
        for (my $i=0; $i<=$_->{page_down}; $i++) {
            checkneedle("test-firefox_printing-".$_->{name}."_".$i,5);
            sendkey "pgdn"; sleep 1;
        }

        sendkey "esc"; sleep 1;
        sendkey "alt-f4"; sleep 1; # Close evince
    }
    
    # Restore and close firefox
    x11_start_program("killall -9 firefox evince"); # Exit firefox. Kill evince at the same time if they are still there.
    x11_start_program("rm -rf .mozilla"); # Clear profile directory
    x11_start_program("rm *.pdf"); # Remove all printed pdf files
    sleep 1;
}   

1;

#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248979
#Description:    Firefox Print
#
#1.Go to http://www.novell.com
#2.Select File-> Print or click the toolbar Print icon.
#3.Print the page and check the hard copy output.
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

    sendkey "ctrl-l"; sleep 1;
    sendautotype "www.novell.com"."\n"; sleep 5;        #open the novell.com
    sendkey "ctrl-p"; sleep 1;
    checkneedle("firefox_print",3);
    for(1..2) {                        #
        sendkey "tab"; sleep 1;
    }
    sendkey "left"; sleep 1;
    sendautotype "/home/".$username."/"."\n";        #firefox-bug 894966
    sleep 5;

#check the pdf file
    x11_start_program("evince /home/".$username."/"."mozilla.pdf");
    sleep 3;
    checkneedle ("firefox_printpdf_evince",5);
    sendkey "alt-f4"; sleep 2;                #close evince
#delete the "mozilla.pdf" file
    x11_start_program("rm /home/".$username."/"."mozilla.pdf");

    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;


#!/usr/bin/perl -w

##################################################
# Written by:    Xudong Zhang <xdzhang@suse.com>
# Case:        1248994
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
    sendautotype "https://pdb.suse.de"."\n"; sleep 5;    #open this site
    checkneedle("firefox_https-risk",3);        #will get untrusted page
    sendkey "ctrl-l"; sleep 1;
    sendautotype "https://svn.provo.novell.com/svn/opsqa/trunk/tests/qa_test_firefox/qa_test_firefox/test_source/pdb.suse.de"."\n"; sleep 5;
    checkneedle("firefox_page-pdbsuse",5);
    sendkey "ctrl-s"; sleep 2;
    checkneedle("firefox_saveas",5);
    sendkey "ctrl-a"; sleep 1;
    sendkey "backspace"; sleep 1;
    sendautotype "/home/".$username."/pdb.suse.de"."\n"; sleep 1;
    
    sendkey "alt-e"; sleep 1;
    sendkey "n"; sleep 1;
    sendkey "left"; sleep 1;            #switch to "Advanced" tab
    sendkey "tab"; sleep 1;                #switch to "General" submenu
    for(1..4) {                    #4 times right  switch to "Encryption"
        sendkey "right"; sleep 1;
    }
    sendkey "alt-s"; sleep 1;            #open the "Certificate Manager"
    sendkey "shift-tab"; sleep 1;            #select the default "Authorities"
    sendkey "left"; sleep 1;
    sendkey "alt-m"; sleep 1;            #Certificate File to Import
    sendkey "slash"; sleep 1;
    sendkey "ret"; sleep 1;
    sendautotype "/home/".$username."/pdb.suse.de"."\n"; sleep 1;
#recover all the changes done to "Preference"
    sendkey "shift-tab"; sleep 1;            #switch to tab "Server"
    sendkey "shift-tab"; sleep 1;
    sendkey "right"; sleep 1;            #switch to tab "Authorities" default
    sendkey "alt-f4"; sleep 1;
    sendkey "shift-tab"; sleep 1;            #switch to tab "Certificates"
    sendkey "shift-tab"; sleep 1;
    for(1..4) {                    #4 times left to switch to "General" sub-menu
        sendkey "left"; sleep 1;
    }
    sendkey "shift-tab"; sleep 1;            #switch to the "Advanced" tab of Preference
    sendkey "right"; sleep 1;            #switch to the "General" tab of Preference

    sendkey "alt-f4"; sleep 1;
    sendkey "ctrl-l"; sleep 1;
    sendautotype "https://pdb.suse.de"."\n"; sleep 5;    #open this site again
    checkneedle("firefox_https-pdbsuse",3);        #will get untrusted page

    
    sendkey "alt-f4"; sleep 2;
    sendkey "ret"; sleep 2; # confirm "save&quit"
}

1;


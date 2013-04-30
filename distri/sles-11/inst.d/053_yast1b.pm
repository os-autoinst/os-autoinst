#!/usr/bin/perl -w
use strict;
use base "installstep";
use bmwqemu;

sub addonproduct()
{
	if($ENV{ADDONURL}) {
		if(!$ENV{NET}) {
			sendkey $cmd{"next"}; waitidle; # use network
			sendkey "alt-o"; waitidle; # OK DHCP network
		}
		my $repo=0;
		foreach my $url (split(/\+/, $ENV{ADDONURL})) {
			if($repo++) {sendkey "alt-a"; waitidle;} # Add another
			sendkey $cmd{"next"}; waitidle; waitstillimage; # Specify URL (default)
			sendautotype($url);
			sendkey $cmd{"next"}; waitidle;
			if($ENV{DISTRI}=~m/^sle/i) {
				waitstillimage(12,30);
				sendkey "alt-o"; # close Beta warning (becomes disagree with license without warning - compensated by alt-y below)
				sleep 2;
				sendkey "alt-y"; # accept Add-On's license
				sleep 2;
				sendkey $cmd{"next"};
			}

			sendkey "alt-i"; waitidle; # confirm import (trust) key
		}
		sendkey $cmd{"next"}; waitidle; # done
	}
}

sub run()
{
  if(!$ENV{LIVECD}) {
	# autoconf phase
        # waitforneedle("systemanalysis", 10);
	waitforneedle("instmode", 15);

	# Installation Mode = new Installation
	if($ENV{UPGRADE}) {
		sendkey "alt-u";
		# TODO
		# waitforneedle("addonproduct-included", 3);
	}
	if($ENV{ADDONURL}) {
		sendkey "alt-c"; # Include Add-On Products
		# TODO
		# waitforneedle("autoconf-deselected", 3);
	}
	sendkey $cmd{"next"};
	waitidle(29);
      if(!$ENV{UPGRADE}) {
	addonproduct();
      } else {
	# upgrade system select
	sendkey "alt-c"; # "Cancel" on warning popup (11.1->11.3)
	waitidle;
	sendkey "alt-s"; # "Show All Partitions"
	waitidle;

	sendkey $cmd{"next"};
	# repos
	waitidle;
	sendkey $cmd{"next"};
	waitidle;
	# might need to resolve conflicts here
	if($ENV{UPGRADE}=~m/11\.1/) {
		sendkey "alt-c";
		waitidle;
		sendkey "p";
		waitidle;
	# alt-c p # Change Packages
		for(1..4) {sendkey "tab"}
		sendkey "spc";
		sleep 3;
		sendkey "alt-o";
	# tab tab tab tab space alt-o # Select+OK
		waitidle;
		sendkey "alt-a";
		waitidle;
		sendkey "alt-o";
	# alt-a alt-o # Accept + Continue(with auto-changes)
	}
	addonproduct();
	waitidle;
	sendkey "alt-c"; # change
	sleep 2;
	sendkey "p";	# Packages
	sleep 60;
	sendkey "alt-a"; # Accept
	sleep 2;
	for(1..7){sendkeyw "alt-a"} # Accept licenses
	sendkey "alt-o"; # cOntinue
	waitidle;
	sendkey "alt-u"; # Update if available
	waitidle 10;
	sendkey "alt-u"; # confirm
	sleep 20;
	sendkey "alt-d"; # details
      }
  }
}

1;

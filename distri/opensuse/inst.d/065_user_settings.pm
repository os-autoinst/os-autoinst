#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	my $self=shift;
	# user setup
	waitinststage "usersettings";
	waitidle; sleep 3;
	sendautotype($realname);
	sendkey "tab";
	#sleep 1;
	sendkey "tab";
	for(1..2) {
		sendautotype("$password\t");
		#sleep 1;
	}
	if($ENV{DOCRUN}) {
		sendkey $cmd{"otherrootpw"};
	}
	# done user setup
	$self->take_screenshot;
	sendkey $cmd{"next"};
	# loading cracklib
	waitidle 6;
	# PW too easy (cracklib)
	$self->take_screenshot;
	sendkey "ret";
	#sleep 1;
	# PW too easy (only chars)
	#sendkey "ret";
	if($ENV{DOCRUN}) { # root user
		waitidle;
		for(1..2) {
			sendautotype("$password\t");
			sleep 1;
		}
		$self->take_screenshot;
		sendkey $cmd{"next"};
		# loading cracklib
		waitidle 6;
		# PW too easy (cracklib)
		sendkey "ret";
		waitidle;
	}
}

1;

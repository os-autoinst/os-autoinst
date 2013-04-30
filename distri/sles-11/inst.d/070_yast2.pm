#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	my $self=shift;
	$ENV{DOCRUN}=1;
	if(0){
		# user setup
		waitinststage "usersettings";
		waitidle 18;
		sendautotype($realname);
		sendkey "tab";
		#sleep 1;
		sendkey "tab";
		for(1..2) {
			sendautotype("$password\t");
			#sleep 1;
		}
		#if($ENV{DOCRUN}) { sendkey $cmd{"otherrootpw"}; } # already default
		# done user setup
		sendkey $cmd{"next"};
		# loading cracklib
		waitidle 6;
		# PW too easy (cracklib)
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
			sendkey $cmd{"next"};
			# loading cracklib
			waitidle 6;
			# PW too easy (cracklib)
			sendkey "ret";
			waitidle;
		}
	}

# overview-generation
waitinststage "installationoverview";
sleep 5;
waitidle 10;

if($ENV{DOCRUN}) {
	sendkey $cmd{change};	# Change
	sleep 2;
	sendkey $cmd{software};	# Software
	# waitidle;
	for(1..3) {
   	        sleep 1;
		sendkey "down";
	}
	sleep 1;
	sendkey "alt-o"; # OK
	sleep 1;
        # TODO check if there is a lincese dialog here
        sendkey $cmd{accept}; # agfa-fonts license
	sleep 1;
}
# TODO check if there is a lincese dialog here
# sendkey $cmd{accept}; # agfa-fonts license
sleep 2;
waitidle;
}

1;

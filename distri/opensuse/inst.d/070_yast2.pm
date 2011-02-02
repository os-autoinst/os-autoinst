#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
# partition based
waitinststage "disk";
sleep 2;
sendkey $cmd{"next"};

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
if($ENV{DOCRUN}) {
	sendkey $cmd{"otherrootpw"};
}
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

# overview-generation
waitinststage "installationoverview";
sleep 5;
waitidle 10;

if($ENV{DOCRUN}) {
	sendkey "alt-c"; # Change
	sendkey "s";    # Software
	waitidle;
	for(1..3) {
		sendkey "down";
	}
	sleep 4;
	sendkey $cmd{accept}; # Accept
	sleep 2;
	sendkey "alt-o"; # cOntinue
	waitidle;
}

# start install
sendkey $cmd{install};
sleep 2;
waitidle 5;
# confirm
sendkey $cmd{install};
waitinststage "performinstallation";
if(!$ENV{LIVECD} && !$ENV{NICEVIDEO}) {
	sleep 5; # view installation details
	sendkey $cmd{instdetails};
}
}

1;

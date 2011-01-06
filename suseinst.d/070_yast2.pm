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
waitinststage "usersettings", 120;
waitidle 18;
sendautotype($realname);
sendkey "tab";
#sleep 1;
sendkey "tab";
for(1..2) {
	sendautotype("$password\t");
	#sleep 1;
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

# overview-generation
waitinststage "installationoverview";
sleep 5;
waitidle 10;
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

#!/usr/bin/perl -w
use strict;
use bmwqemu;

if(1){
# license+lang
sendkey $cmd{"next"};
# autoconf
sleep 18;
# new inst
sendkey $cmd{"next"};
# timezone
sleep 5;
sendkey $cmd{"next"};
# KDE
sleep 3;
sendkey $cmd{"next"};
# partition based
sleep 4;
system("./autoinst-partitions.pl");
}
sendkey $cmd{"next"};

# user setup
sleep 5;
print autotype("bernhard");
sendkey "tab";
sleep 1;
sendkey "tab";
for(1..2) {
	print ((autotype("notsecret")."sendkey tab\n"));
	sleep 1;
}
# done user setup
sendkey $cmd{"next"};
# loading cracklib
sleep 3;
# PW too easy (cracklib)
sendkey "ret";
sleep 1;
# PW too easy (only chars)
sendkey "ret";

# overview-generation
sleep 15;
# start install
sendkey $cmd{install};
sleep 2;
# confirm
sendkey $cmd{install};


#!/usr/bin/perl -w
use strict;
use bmwqemu;

if(1){
# license+lang
sendkey "alt-w";
# autoconf
sleep 18;
# new inst
sendkey "alt-w";
# timezone
sleep 5;
sendkey "alt-w";
# KDE
sleep 3;
sendkey "alt-w";
# partition based
sleep 4;
system("./autoinst-partitions.pl");
}
sendkey "alt-w";

# user setup
sleep 5;
print autotype("bernhard");
print "sendkey tab\n";
sleep 1;
print "sendkey tab\n";
for(1..2) {
	print ((autotype("notsecret")."sendkey tab\n"));
	sleep 1;
}
# done user setup
print "sendkey alt-w\n";
# loading cracklib
sleep 3;
# too easy
print "sendkey ret\n";
sleep 1;
print "sendkey ret\n";

# overview-generation
sleep 15;
# start install
print "sendkey alt-i\n";
sleep 2;
# confirm
print "sendkey alt-i\n";


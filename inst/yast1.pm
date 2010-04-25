#!/usr/bin/perl -w
use strict;
use bmwqemu;

if($ENV{BETA}) {
	sendkey "ret";
	sendkey $cmd{acceptlicense};
}
# license+lang
sendkey $cmd{"next"};
# autoconf
waitidle 30;
# new inst
sendkey $cmd{"next"};
# timezone
waitidle;
sendkey $cmd{"next"};
# KDE
waitidle;
sendkey $cmd{"next"};
waitidle;
# ending at partition layout screen

1;

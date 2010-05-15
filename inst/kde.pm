#!/usr/bin/perl -w
use strict;
use bmwqemu;

# wait until ready
waitinststage "KDE", 1000;
waitidle 100;
sleep 10;

my $lastmenu=0;
# open KDE menu
sub open_menu($;$)
{ my $n=shift; my $wait=shift;
	sendkey "alt-f1";
	waitidle;
	my $diff=$n-$lastmenu;
	$lastmenu=$n;
	if($diff<0) {
		for(1..-$diff) {
			sendkey "up";
		}
	}
	if($diff>0) {
		for(1..$diff) {
			sendkey "down";
		}
	}
	sleep 1;
	sendkey "ret";
	waitidle $wait;
	sleep 4;
}

my %kdemenu=(firefox=>1, pim=>2, office=>3, audio=>4, fileman=>5, config=>6, help=>7, xterm=>8);

open_menu($kdemenu{firefox});
open_menu($kdemenu{office});
open_menu($kdemenu{help});
open_menu($kdemenu{pim}, 100);
sleep 10; waitidle 100; sleep 10; # pim needs extra time for first init
open_menu($kdemenu{config});
open_menu($kdemenu{fileman});
open_menu($kdemenu{audio});
open_menu($kdemenu{xterm});
sendautotype "sudo /sbin/yast2 lan\n$password\n";

1;

use base "basetest";
use strict;
use bmwqemu;

sub x() {sleep 1};
sub run()
{
	waitidle;
	sendkey "ret"; # partitioning = guided whole disk
	x; sendkey "ret"; # select first disk
	x; sendkey "ret"; # all files in one part
	x; sendkey "ret"; # finish
	x; sendkey "tab"; sendkey "ret"; # confirm partitioning
}

1;

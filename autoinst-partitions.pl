#!/usr/bin/perl -w
use strict;
use bmwqemu;

# add a new primary partition
sub addpart($$)
{
	my ($size,$type)=@_;
	sendkey "alt-h";
	sleep 4;
	sendkey "alt-w";
	sleep 3;
	for(1..10) {
		sendkey "backspace";
	}
	sleep 1;
	print autotype($size."mb");
	sleep 1;
	sendkey "alt-w";
	sleep 3;
	sendkey "alt-n";
	sleep 1;
	sendkey "alt-i";
	sleep 1;
	for(1..$type) {
		sendkey "down";
	}
	sleep 1;
	sendkey "alt-b";
	sleep 3;
}

sub addraid($)
{
	my($step)=@_;
	for(1..3) {
		sendkey "spc";
		for(1..$step) {
			sleep 1;
			sendkey "ctrl-down";
		}
		sendkey "spc";
	}
	# add
	sendkey "alt-h";
	sleep 1;
	sendkey "alt-w";
	sleep 2;
	sendkey "alt-w";
	sleep 3;
}





if(1) {
# create partitioning
sendkey "alt-e";
sleep 3;
# user defined
sendkey "alt-b";
sendkey "alt-w";
sleep 9;

sendkey "tab";
sendkey "down"; # select disks
sendkey "right"; # unfold disks
sendkey "down"; # select first disk
for (1..4) {
	addpart(100, 3); # boot
	addpart(3300, 3); # root
	addpart(300, 3); # swap
	# select next disk
	sendkey "shift-tab";
	sendkey "shift-tab";
	sendkey "down";
	sleep 1;
}

# select RAID add
sendkey "alt-i";
sleep 4;
sendkey "alt-d"; # RAID 6 for /
sleep 1;
for(1..2) {
	sendkey "tab";
	sleep 1;
}
sendkey "down";
sleep 1;
addraid(3);
sendkey "alt-b";
sleep 3;


# select RAID add
sendkey "alt-i";
sleep 4;
sendkey "alt-1"; # RAID 1 for /boot
for(1..4) {
	sleep 1;
	sendkey "tab";
}
sleep 1;
addraid(2);

sendkey "alt-e";
for(1..3) {
	sleep 1;
	sendkey "down";
}
sendkey "alt-b";
sleep 3;

}

# select RAID add
sendkey "alt-i";
sleep 4;
sendkey "alt-0"; # RAID 0 for swap
for(1..5) {
	sleep 1;
	sendkey "tab";
}
sleep 1;
addraid(1);

sendkey "alt-s";
sleep 1;
sendkey "end";
sleep 1;
sendkey "alt-b";
sleep 3;


# done
sendkey "alt-r";
sleep 4;


#!/usr/bin/perl -w
use strict;
use bmwqemu;

# add a new primary partition
sub addpart($$)
{
	my ($size,$type)=@_;
	sendkey $cmd{addpart};
	sleep 4;
	sendkey $cmd{"next"};
	sleep 3;
	for(1..10) {
		sendkey "backspace";
	}
	sleep 1;
	print autotype($size."mb");
	sleep 1;
	sendkey $cmd{"next"};
	sleep 3;
	sendkey $cmd{"donotformat"};
	sleep 1;
	sendkey "tab";
	sleep 1;
	for(1..$type) {
		sendkey "down";
	}
	sleep 1;
	sendkey $cmd{finish};
	sleep 3;
}

sub addraid($)
{
	my($step)=@_;
	sendkey "spc";
	for(1..3) {
		for(1..$step) {
			sleep 1;
			sendkey "ctrl-down";
		}
		sendkey "spc";
	}
	# add
	sendkey $cmd{"add"};
	sleep 1;
	sendkey $cmd{"next"};
	sleep 2;
	sendkey $cmd{"next"};
	sleep 3;
}





if(1) {
# create partitioning
sendkey $cmd{createpartsetup};
sleep 3;
# user defined
sendkey $cmd{custompart};
sendkey $cmd{"next"};
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
sendkey $cmd{addraid};
sleep 4;
sendkey $cmd{"raid6"}; # RAID 6 for /
sleep 1;
for(1..2) {
	sendkey "tab";
	sleep 1;
}
sendkey "down";
sleep 1;
addraid(3);
sendkey $cmd{"finish"};
sleep 3;


# select RAID add
sendkey $cmd{addraid};
sleep 4;
sendkey $cmd{raid1}; # RAID 1 for /boot
for(1..4) {
	sleep 1;
	sendkey "tab";
}
sleep 1;
addraid(2);

sendkey $cmd{"mountpoint"};
for(1..3) {
	sleep 1;
	sendkey "down";
}
sendkey $cmd{"finish"};
sleep 3;

}

# select RAID add
sendkey $cmd{addraid};
sleep 4;
sendkey $cmd{raid0}; # RAID 0 for swap
for(1..5) {
	sleep 1;
	sendkey "tab";
}
sleep 1;
addraid(1);

# select file-system
sendkey $cmd{filesystem};
sleep 1;
sendkey "end"; # swap at end of list
sleep 1;
sendkey $cmd{"finish"};
sleep 3;


# done
sendkey $cmd{"accept"};
sleep 4;


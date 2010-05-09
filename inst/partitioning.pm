#!/usr/bin/perl -w
use strict;
use bmwqemu;

# add a new primary partition
sub addpart($$)
{
	my ($size,$type)=@_;
	sendkey $cmd{addpart};
	waitidle 4;
	sendkey $cmd{"next"};
	waitidle 3;
	for(1..10) {
		sendkey "backspace";
	}
	sendautotype($size."mb");
	sendkey $cmd{"next"};
	waitidle 3;
	sendkey $cmd{"donotformat"};
	sendkey "tab";
	for(1..$type) {
		sendkey "down";
	}
	sendkey $cmd{finish};
	waitidle 3;
}

sub addraid($)
{
	my($step)=@_;
	sendkey "spc";
	for(1..3) {
		for(1..$step) {
			sendkey "ctrl-down";
		}
		sendkey "spc";
	}
	# add
	sendkey $cmd{"add"};
	waitidle 3;
	sendkey $cmd{"next"};
	waitidle 3;
	sendkey $cmd{"next"};
	waitidle 3;
}



if(1) {
# create partitioning
sendkey $cmd{createpartsetup};
waitidle 3;
# user defined
sendkey $cmd{custompart};
sendkey $cmd{"next"};
waitidle 9;

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
}

# select RAID add
sendkey $cmd{addraid};
waitidle 4;

if(!$ENV{INSTRAID10}) { # RAID6
	sendkey $cmd{"raid6"}; # RAID 6 for /
	for(1..2) {
		sendkey "tab";
	}
} else { # RAID10
	sendkey $cmd{"raid10"}; # RAID 10 for /
	sendkey "tab";
}
sendkey "down";
addraid(3);
sendkey $cmd{"finish"};
waitidle 3;


# select RAID add
sendkey $cmd{addraid};
waitidle 4;
sendkey $cmd{raid1}; # RAID 1 for /boot
for(1..4) {
	sendkey "tab";
}
addraid(2);

sendkey $cmd{"mountpoint"};
for(1..3) {
	sendkey "down";
}
sendkey $cmd{"finish"};
waitidle 3;

}

# select RAID add
sendkey $cmd{addraid};
waitidle 4;
sendkey $cmd{raid0}; # RAID 0 for swap
for(1..5) {
	sendkey "tab";
}
addraid(1);

# select file-system
sendkey $cmd{filesystem};
sendkey "end"; # swap at end of list
sendkey $cmd{"finish"};
waitidle 3;


# done
sendkey $cmd{"accept"};
waitidle 4;

1;

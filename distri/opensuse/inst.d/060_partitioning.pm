#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
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

sub addraid($;$)
{
	my($step, $chunksize)=@_;
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
	# chunk size selection
	if($chunksize) {
		sendautotype("\t$chunksize");
	}
	sendkey $cmd{"next"};
	waitidle 3;
}

sub setraidlevel($)
{
	my $level=shift;
	my %entry=(0=>0, 1=>1, 5=>2, 6=>3, 10=>4);
	for(0..$entry{$level}) {
		sendkey "tab";
	}
	sendkey "spc"; # set entry
	for($entry{$level}..$entry{10}) {
		sendkey "tab";
	}
}


waitinststage "disk";
if(defined($ENV{RAIDLEVEL})) {
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

if(!defined($ENV{RAIDLEVEL})) {$ENV{RAIDLEVEL}=6}
setraidlevel($ENV{RAIDLEVEL});
sendkey "down"; # start at second partition (i.e. sda2)
addraid(3,6);
sendkey $cmd{"finish"};
waitidle 3;


# select RAID add
sendkey $cmd{addraid};
waitidle 4;
setraidlevel(1); # RAID 1 for /boot
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
setraidlevel(0); # RAID 0 for swap
addraid(1);

# select file-system
sendkey $cmd{filesystem};
sendkey "end"; # swap at end of list
sendkey $cmd{"finish"};
waitidle 3;


# done
sendkey $cmd{"accept"};
waitidle 4;
sleep 2;
} elsif($ENV{LVM}) {
	sendkey "alt-l"; # enable LVM-based proposal
	waitidle;
}
}

1;

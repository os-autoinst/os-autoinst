#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;


# add a new primary partition
#   $type == 3 => 0xFD Linux RAID
sub addpart($$)
{
    my ($size,$type)=@_;
    sendkey $cmd{addpart};
    waitidle 4;
    sendkey $cmd{"next"};
    waitidle 3;
    for (1..10) {
	sendkey "backspace";
    }
    sendautotype($size."mb");
    waitidle 3;
    sendkey $cmd{"next"};
    waitidle 3;
    sendkey $cmd{"donotformat"};
    waitidle 3;
    sendkey "tab";
    waitidle 3;
    for (1..$type) {
	waitidle 3;
	sendkey "down";
    }
    waitidle 3;
    sendkey $cmd{finish};
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


# Entry test code
sub run()
{
    waitforneedle('partioning', 40);
    if($ENV{TOGGLEHOME} && !$ENV{LIVECD}) {
	my $homekey=checkEnv('VIDEOMODE', "text")?"alt-p":"alt-h";
	sendkey $homekey;
	waitforneedle("disabledhome", 10);
    }

    if(defined($ENV{RAIDLEVEL})) {
	# create partitioning
	sendkey $cmd{createpartsetup};
	waitforneedle('createpartsetup', 3);
	# user defined
	sendkey $cmd{custompart};
	sendkey $cmd{"next"};
	waitforneedle('custompart', 9);

	sendkey "tab";
	sendkey "down"; # select disks
	sendkey "right"; # unfold disks
	sendkey "down"; # select first disk
	waitidle 5;

	for (1..4) {
	    addpart(100, 3); # boot
	    addpart(5300, 3); # root
	    addpart(300, 3); # swap
	    waitforneedle('raid-partition', 5);
	    # select next disk
	    sendkey "shift-tab";
	    sendkey "shift-tab";
	    sendkey "down";
	}

	# select RAID add
	sendkey $cmd{addraid};
	waitidle 4;

	if(!defined($ENV{RAIDLEVEL})) { $ENV{RAIDLEVEL}=6 }
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
	for (1..3) {
	    sendkey "down";
	}
	sendkey $cmd{"finish"};
	waitidle 3;

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
	waitforneedle('acceptedpartioning', 6);
    } elsif ($ENV{BTRFS}) {
	sendkey "alt-u";  # Use btrfs
	waitforneedle('usebtrfs', 3);
    }
}

1;

#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;


sub is_applicable()
{
    my $self=shift;
    return $self->SUPER::is_applicable && !$ENV{UPGRADE};
}


# add a new primary partition
#   $type == 3 => 0xFD Linux RAID
sub addpart($$)
{
    my ($size,$type)=@_;
    sendkey $cmd{addpart};
    waitidle 5;
    sendkey $cmd{"next"};
    waitidle 5;
    # the input point at the head of the lineedit, move it to the end
    if($ENV{GNOME}) { sendkey "end" }
    for (1..10) {
	sendkey "backspace";
    }
    sendautotype($size."mb");
    waitidle 5;
    sendkey $cmd{"next"};
    waitidle 5;
    sendkey $cmd{"donotformat"};
    waitidle 5;
    sendkey "tab";
    waitidle 5;
    for (1..$type) {
	waitidle 5;
	sendkey "down";
    }
    waitidle 5;
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
	# in GNOME Live case, press space will direct added this item
	if($ENV{GNOME}) {
	    sendkey "ctrl-spc";
        } else {
	    sendkey "spc";
        }
    }
    # add
    sendkey $cmd{"add"};
    waitidle 3;
    sendkey $cmd{"next"};
    waitidle 3;
    # chunk size selection
    if($chunksize) {
	# workaround for gnomelive with chunksize 64kb
	if($ENV{GNOME}) {
	    sendkey "alt-c";
	    sendkey "home";
	    for (1..4) {
	        sendkey "down";
	    }
        } else {
	    sendautotype("\t$chunksize");
	}
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
    # skip RAID name input
    sendkey "tab";
}


# Entry test code
sub run()
{
    waitforneedle('partitioning', 40);

    if($ENV{DUALBOOT}) {
	waitforneedle('partitioning-windows', 40);
    }

    # XXX: why is that here?
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
	# seems GNOME tree list didn't eat right arrow key
	if($ENV{GNOME}) {
	    sendkey "spc"; # unfold disks
        } else {
	    sendkey "right"; # unfold disks
	}
	sendkey "down"; # select first disk
	waitidle 5;

	for (1..4) {
	    waitidle 5;
	    addpart(100, 3); # boot
	    waitidle 5;
	    addpart(5300, 3); # root
	    waitidle 5;
	    addpart(300, 3); # swap
	    waitforneedle('raid-partition', 5);
	    # select next disk
	    sendkey "shift-tab";
	    sendkey "shift-tab";
	    # walk through sub-tree
	    if($ENV{GNOME}) {
	        for (1..3) { sendkey "down" }
	    }
	    sendkey "down";
	}

	# select RAID add
	sendkey $cmd{addraid};
	waitidle 4;

	if(!defined($ENV{RAIDLEVEL})) { $ENV{RAIDLEVEL}=6 }
	setraidlevel($ENV{RAIDLEVEL});
	sendkey "down"; # start at second partition (i.e. sda2)
	# in this case, press down key doesn't move to next one but itself
	if($ENV{GNOME}) { sendkey "down" }
	addraid(3,6);
	# workaround for gnomelive, double alt-f available in same page
	if($ENV{GNOME}) {
	    sendkey "spc";
        } else {
	    sendkey $cmd{"finish"};
	}
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
	# workaround for gnomelive, double alt-f available in same page
	if($ENV{GNOME}) {
            sendkey $cmd{"finish"};
	    sendkey "spc";
        }
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
	waitforneedle('acceptedpartitioning', 6);
    } elsif ($ENV{BTRFS}) {
	sendkey "alt-u";  # Use btrfs
	waitforneedle('usebtrfs', 3);
    }
}

1;

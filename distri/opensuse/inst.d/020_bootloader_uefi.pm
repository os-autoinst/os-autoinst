use base "basetest";
use strict;
use bmwqemu;
use Time::HiRes qw(sleep);

sub is_applicable()
{
  return $ENV{UEFI};
}

# hint: press shift-f10 trice for highest debug level
sub run()
{
	waitforneedle("bootloader-grub2",15);
	if($ENV{QEMUVGA} && $ENV{QEMUVGA} ne "cirrus") {
		sleep 5;
	}
	if($ENV{ZDUP} || $ENV{WDUP}) {
		qemusend "eject -f ide1-cd0";
		qemusend "system_reset";
		sleep 10;
		sendkey "ret"; # boot
		return;
	}

if($ENV{MEDIACHECK}) { # special
	# only run this one
	for(1..2) {
		sendkey "down";
	}
	sleep 3;
	sendkey "ret";
  return;
}
# assume bios+grub+anim already waited in start.sh
if(!$ENV{LIVETEST}) {
        # in grub2 it's tricky to set the screen resolution
        sendkey "e";
        for(1..4) {sendkey "down";}
        sendkey "end";
        sendkey "spc";
} else {
	if($ENV{PROMO}) {
		for(1..2) {sendkey "down";} # select KDE Live
	}
}

# 1024x768
if($ENV{RES1024}) { # default is 800x600
        sendautotype("video=1280x1024-16 ");
} elsif($ENV{VIDEOMODE} eq "text") {
	#sendkey "f3";
	#for(1..2) {
	#	sendkey "up";
	#}
	#sendkey "ret";
} else {
    sleep 10;
    sendautotype("video=800x600-16 ");
}

#sendautotype("nohz=off "); # NOHZ caused errors with 2.6.26
#sendautotype("nomodeset "); # coolo said, 12.3-MS0 kernel/kms broken with cirrus/vesa #fixed 2012-11-06
if(!$ENV{NICEVIDEO}) {
	sleep 15; sendautotype("console=ttyS0 "); # to get crash dumps as text
	sleep 15; sendautotype("console=tty "); # to get crash dumps as text
	my $e=$ENV{EXTRABOOTPARAMS};
#	if($ENV{RAIDLEVEL}) {$e="linuxrc=trace"}
	if($e) {sleep 10;sendautotype("$e ");}
	sleep 15; # workaround slow gfxboot drawing 662991
}
#sendautotype("kiwidebug=1 ");

#if($ENV{BTRFS}) {sleep 9; sendautotype("squash=0 loadimage=0 ");sleep 21} # workaround 697671

if($ENV{ISO}=~m/i586/) {
#	sendautotype("info=");sleep 4; sendautotype("http://zq1.de/i "); sleep 15; sendautotype("insecure=1 "); sleep 15;
}
    my $args="";
		if($ENV{AUTOYAST}) {
			$args.=" netsetup=dhcp,all autoyast=$ENV{AUTOYAST} ";
		}
    sendautotype $args;
if(0 && $ENV{RAIDLEVEL}) {
	# workaround bnc#711724
	$ENV{ADDONURL}="http://download.opensuse.org/repositories/home:/snwint/openSUSE_Factory/"; #TODO: drop
	$ENV{DUD}="dud=http://zq1.de/bl10";
	sendautotype("$ENV{DUD} ");sleep 20;
	sendautotype("insecure=1 ");sleep 20;
}

if($ENV{LIVETEST} && $ENV{LIVEOBSWORKAROUND}) {
	sendkey("1");   # runlevel 1
	sendkey("f10"); # boot
	sleep(40);
	sendautotype("
ls -ld /tmp
chmod 1777 /tmp
init 5
exit
");

}

qemusend "boot_set c"; # boot from HDD next time

# boot
sendkey "f10";

}

1;

use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "4"; # hard drives
	sendkey "ret"; # ok
	sleep 1;
	sendkey "ret"; # auto prepare ok
	sleep 1;
	sendkey "end"; # select sda
	sleep 1;
	sendkey "ret"; # size boot part ok
	sleep 1;
	sendkey "ret"; # size swap part ok
	sleep 1;
	sendkey "ret"; # size root part ok
	sleep 1;
	sendkey "ret"; # size home part ok
	sleep 1;
	if($ENV{BTRFS}) {
		sendkey "b"; # btrfs
	}
	else {
		sendkey "e"; # ext3
		sendkey "e"; # ext4
	}
	sendkey "ret"; # select file system
	sleep 1;
	sendkey "ret"; # format disk ok
	sleep 1;
	$self->take_screenshot;
	waitstillimage(12,60);
	$self->take_screenshot;
	sleep 1;
	sendkey "ret"; # close info box
	sleep 1;
	sendkey "ret"; # back
}

1;

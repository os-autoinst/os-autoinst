use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "5"; # packages
	sendkey "ret"; # ok
	waitidle 12;
	sendkey "ret"; # close info box
	sleep 1;
	sendkey "ret"; # bootloader grub ok
	sleep 1;
	sendkey "ret"; # base pkg group  ok
	sleep 1;
	if($ENV{NETINST}) {
		for (1..5) {sendkey "c";}
		sleep 1;
		sendkey "spc"; # select curl
	}
	sleep 1;
	$self->take_screenshot;
	sleep 2;
	sendkey "ret"; # pkgs to install ok
}

1;

use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "1"; # source
	sendkey "ret"; # ok
	sleep 4;
	$self->take_screenshot;
	sleep 6;
	sendkey "ret"; # ok
	sleep 6;
	if($ENV{NETBOOT}) {
		$self->take_screenshot;
		sleep 1;
		sendkey "ret"; # close info box
		sleep 4;
		$self->take_screenshot;
		sleep 1;
		sendkey "h"; # http mirror
		sleep 1;
		$self->take_screenshot;
		sleep 2;
		sendkey "ret"; # ok
		sleep 3;
		sendkey "ret"; # setup network
		sleep 2;
		sendkey "ret"; # close info box
		sleep 2;
		$self->take_screenshot;
		sleep 1;
		sendkey "ret"; # use nic
		sleep 2;
		sendkey "ret"; # use dhcp
		sleep 16;
		sendkey "ret"; # close info box
		sleep 1;
	}
}

1;

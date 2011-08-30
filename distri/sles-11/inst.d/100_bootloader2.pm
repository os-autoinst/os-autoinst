use strict;
use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	waitinststage("bootloader",15); # skip anim
	sendkey "ret"; # boot from HDD (in DVD isolinux)
	$self->take_screenshot;
	sleep 3;
}

1;

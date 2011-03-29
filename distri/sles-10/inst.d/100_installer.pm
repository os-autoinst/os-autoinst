use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	$bmwqemu::idlethreshold+=5;
	# extra wait for slow usb detect
	waitinststage("installer-language");
	mousemove_raw(31000, 31000); # move mouse off screen
	$self->take_screenshot;
	sendkeyw("alt-n"); # language
	if(0) { # missing in SLES-10-SP4-GM - but was in RC3
		# media check
		$self->take_screenshot;
		sendkeyw("alt-n");
	}
	if($ENV{BETA}) {
		# beta warning
		$self->take_screenshot;
		sendkeyw("alt-o");
	}
	# license agreement
	$self->take_screenshot;
	sendkey("alt-y"); # yes
	sendkeyw("alt-n");
	# install mode
	$self->take_screenshot;
	sendkeyw("alt-n");
}

1;

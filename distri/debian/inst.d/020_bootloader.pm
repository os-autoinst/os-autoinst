use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sleep 8;
	$self->take_screenshot; sleep 1;
	# boot
	sendkey "ret";
}

1;

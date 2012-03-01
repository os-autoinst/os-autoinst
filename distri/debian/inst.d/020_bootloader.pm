use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sleep 5;
	waitstillimage;
	$self->take_screenshot; sleep 1;
	# boot
	sendkey "ret";
	sleep 2;
}

1;

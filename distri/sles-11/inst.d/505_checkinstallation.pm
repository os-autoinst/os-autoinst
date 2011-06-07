use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	sleep 2;
	$self->take_screenshot;
	waitidle;
}

1;

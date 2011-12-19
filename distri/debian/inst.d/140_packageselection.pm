use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	$self->take_screenshot; sleep 1;
	# default = system+desktop
	sendkey "ret"; # accept
}

1;

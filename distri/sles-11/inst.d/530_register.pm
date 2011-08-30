use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	# Online Update / novell customer center
	sendkey "alt-c"; # configure later
	sleep 2;
	$self->take_screenshot;
	sendkey "alt-n";
	waitidle(90);
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	$self->take_screenshot;
        sendkeyw "alt-n";
	sleep 10;
	waitidle; #TODO waitinststage
}

1;

use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Service
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;

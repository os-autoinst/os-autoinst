use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Release Notes
        sleep 14;
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;

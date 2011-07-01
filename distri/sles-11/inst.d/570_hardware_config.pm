use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Hardware Configuration
        sendkeyw "alt-o"; # OK probe graphics card
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;

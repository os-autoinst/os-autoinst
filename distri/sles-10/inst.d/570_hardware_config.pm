use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Hardware Configuration
	$self->take_screenshot;
        sendkeyw "alt-n";

        # Completed
	$self->take_screenshot;
        sendkey "alt-f"; # finish
        sleep 20;
        waitidle(50);
        # done booting first time here
	$self->take_screenshot;
}

1;

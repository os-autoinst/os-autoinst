use base "basetest";
use strict;
use bmwqemu;

sub sendkeyw($) {sendkey(shift); waitidle;}

sub run()
{ my $self=shift;
        # Service / Installation Settings
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;

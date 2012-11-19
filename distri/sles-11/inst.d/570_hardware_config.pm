use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitstillimage;
        # Hardware Configuration
        sendkeyw "alt-o"; # OK probe graphics card
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;

use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitstillimage(20,60);
	mouse_hide;
	$self->take_screenshot;
        sendkeyw "alt-n";
	sleep 10;
	waitstillimage(20,60);
}

1;

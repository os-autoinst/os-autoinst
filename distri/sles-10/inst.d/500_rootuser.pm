use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;

	mouse_hide(1);
	sendautotype "$password\t"; # root PW
	sendautotype "$password";
	$self->take_screenshot;
        sendkeyw "alt-n";
}

1;
